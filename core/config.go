package core

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/age"
	"github.com/metacubex/mihomo/component/auth"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	authStore "github.com/metacubex/mihomo/listener/auth"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"go.yaml.in/yaml/v3"
)

var (
	configMu      sync.Mutex
	currentConfig *config.Config

	errConfigNotApplied = errors.New("config is not applied")
	errNotInitialized   = errors.New("not initialized")
)

var setupConfig = applyConfig

func handleSetupConfig(params *SetupParams) error {
	if !isInit.Load() {
		return errNotInitialized
	}
	return setupConfig(params)
}

func handleReadConfig(params PathParams) (*config.RawConfig, error) {
	return readRawConfig(params.Path)
}

func readRawConfig(path string) (*config.RawConfig, error) {
	defer scheduleLoadMemoryRelease()
	buf, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return unmarshalRawConfig(buf)
}

func handleGetProxyDefinition(params NameParams) (map[string]any, error) {
	name := params.Name
	raw, err := readRawConfig(runningConfigPath())
	if err != nil {
		return nil, err
	}
	if proxy := lookupProxy(name); proxy != nil {
		if pdName := proxy.ProxyInfo().ProviderName; pdName != "" {
			if _, running := tunnel.Providers()[pdName]; !running {
				return nil, nil
			}
			if _, declared := raw.ProxyProvider[pdName]; !declared {
				return nil, nil
			}
			if mapping := providerProxyDefinition(pdName, proxy.Name()); mapping != nil {
				return mapping, nil
			}
			return nil, nil
		}
	}
	for _, mapping := range raw.Proxy {
		if mapping["name"] == name {
			return mapping, nil
		}
	}
	return nil, nil
}

func handleValidateConfig(params PathParams) *string {
	if _, err := readRawConfig(params.Path); err != nil {
		message := err.Error()
		return &message
	}
	return nil
}

func handleDecryptConfig(params DecryptConfigParams) (string, error) {
	buf, err := os.ReadFile(params.Path)
	if err != nil {
		return "", err
	}
	buf, err = age.DecryptBytes(buf, params.AgeSecretKey)
	if err != nil {
		return "", err
	}
	return string(buf), nil
}

// mihomo writes the NTP time with settimeofday, which Android's app seccomp
// policy answers by killing the process rather than with EPERM.
var systemTimeWritable = runtime.GOOS != "android"

func loadConfig(path string) (*config.Config, error) {
	buf, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	cfg, err := executor.ParseWithBytes(buf)
	if err != nil {
		return nil, err
	}
	return withPlatformLimits(cfg), nil
}

func withPlatformLimits(cfg *config.Config) *config.Config {
	if cfg.NTP.WriteToSystem && !systemTimeWritable {
		log.Warnln("ntp write-to-system ignored: Android does not let apps set the system time")
		cfg.NTP.WriteToSystem = false
	}
	return cfg
}

func runningConfigPath() string {
	return filepath.Join(constant.Path.HomeDir(), "config.yaml")
}

func loadSetupConfig(params *SetupParams) (*config.Config, error) {
	path := runningConfigPath()
	if params.Base != nil {
		return loadConfigWithBase(params.Base, path)
	}
	return loadConfig(path)
}

func applyConfig(params *SetupParams) error {
	runtime.GC()
	configMu.Lock()
	defer configMu.Unlock()

	applyOptions(params.Options)
	cfg, err := loadSetupConfig(params)
	if err != nil {
		// The fallback is what keeps the listeners serving while the host
		// reports the error, but it applies a config with no proxies in it.
		// From the UI that is indistinguishable from a subscription that went
		// dead: the profile still lists every node, every delay test answers
		// Timeout, and nothing routes. Name the real cause in the log.
		logError(
			"config apply failed, falling back to the built-in default - no proxies will be available: %v",
			err,
		)
		fallback, fallbackErr := config.ParseRawConfig(config.DefaultRawConfig())
		if fallbackErr != nil {
			return err
		}
		cfg = fallback
	}

	currentConfig = cfg
	hub.ApplyConfig(cfg)
	patchSelectGroup(params.SelectedMap)
	bumpRouteEpoch()
	updateListeners(cfg)
	reconcileGeoUpdater()
	scheduleLoadMemoryRelease()
	if err != nil {
		// The host tells this apart from a call that failed: the default config runs.
		return &MethodError{Code: "config_rejected", Message: err.Error()}
	}
	return nil
}

func updateConfig(params *UpdateParams) error {
	configMu.Lock()
	defer configMu.Unlock()
	if currentConfig == nil {
		return errConfigNotApplied
	}

	general := currentConfig.General
	if params.MixedPort != nil {
		general.MixedPort = *params.MixedPort
	}
	if params.AllowLan != nil {
		general.AllowLan = *params.AllowLan
	}
	if params.FindProcessMode != nil {
		general.FindProcessMode = *params.FindProcessMode
		tunnel.SetFindProcessMode(general.FindProcessMode)
	}
	if params.TCPConcurrent != nil {
		general.TCPConcurrent = *params.TCPConcurrent
		dialer.SetTcpConcurrent(general.TCPConcurrent)
	}
	if params.UnifiedDelay != nil {
		general.UnifiedDelay = *params.UnifiedDelay
		adapter.UnifiedDelay.Store(general.UnifiedDelay)
	}
	routeChange := routeUnchanged
	if params.Mode != nil {
		if general.Mode != *params.Mode {
			routeChange = routeMoved
		}
		general.Mode = *params.Mode
		tunnel.SetMode(general.Mode)
	}
	if params.LogLevel != nil {
		general.LogLevel = *params.LogLevel
		log.SetLevel(general.LogLevel)
	}
	// Turning IPv6 on moves a direct dial to another exit address while the
	// route it takes stays the same.
	if params.IPv6 != nil {
		if general.IPv6 != *params.IPv6 {
			routeChange = routeReset
		}
		general.IPv6 = *params.IPv6
		resolver.DisableIPv6 = !general.IPv6
	}
	if params.Tun != nil {
		patchTun(&general.Tun, params.Tun)
	}
	patchController(params)
	if params.Authentication != nil {
		applyAuthentication(currentConfig, *params.Authentication)
	}
	if params.Options != nil {
		applyOptions(*params.Options)
	}

	updateListeners(currentConfig)
	for geoType, link := range params.GeoXUrl {
		setGeoResourceUrl(geoType, link)
	}
	syncGeoUpdater(params.GeoAutoUpdate, params.GeoUpdateInterval)
	if routeChange != routeUnchanged {
		changeRoute(routeChange)
	}
	return nil
}

func applyOptions(options CoreOptions) {
	setTestURL(options.TestURL)
	skipCertVerify.Store(options.SkipCertVerify)
}

func patchTun(target *LC.Tun, params *tunSchema) {
	target.Enable = params.Enable
	if params.AutoRoute != nil {
		target.AutoRoute = *params.AutoRoute
	}
	if params.Device != nil {
		target.Device = *params.Device
	}
	if params.Stack != nil {
		target.Stack = *params.Stack
	}
}

func routeConfig(cfg *config.Config) *route.Config {
	controller := cfg.Controller
	routeCfg := &route.Config{
		Addr:        controller.ExternalController,
		TLSAddr:     controller.ExternalControllerTLS,
		UnixAddr:    controller.ExternalControllerUnix,
		PipeAddr:    controller.ExternalControllerPipe,
		RoutingMark: controller.ExternalControllerRoutingMark,
		Secret:      controller.Secret,
		DohServer:   controller.ExternalDohServer,
		IsDebug:     cfg.General.LogLevel == log.DEBUG,
		Cors: route.Cors{
			AllowOrigins:        controller.Cors.AllowOrigins,
			AllowPrivateNetwork: controller.Cors.AllowPrivateNetwork,
		},
	}
	if cfg.TLS != nil {
		routeCfg.Certificate = cfg.TLS.Certificate
		routeCfg.PrivateKey = cfg.TLS.PrivateKey
		routeCfg.ClientAuthType = cfg.TLS.ClientAuthType
		routeCfg.ClientAuthCert = cfg.TLS.ClientAuthCert
		routeCfg.EchKey = cfg.TLS.EchKey
	}
	return routeCfg
}

func patchController(params *UpdateParams) {
	controller := currentConfig.Controller
	address, secret := controller.ExternalController, controller.Secret
	if params.ExternalController != nil {
		address = *params.ExternalController
	}
	if params.Secret != nil {
		secret = *params.Secret
	}
	if address == controller.ExternalController && secret == controller.Secret {
		return
	}
	controller.ExternalController, controller.Secret = address, secret
	route.ReCreateServer(routeConfig(currentConfig))
}

func applyAuthentication(cfg *config.Config, authentication []string) {
	users := make([]auth.AuthUser, 0, len(authentication))
	for _, line := range authentication {
		if user, pass, found := strings.Cut(line, ":"); found {
			users = append(users, auth.AuthUser{User: user, Pass: pass})
		}
	}
	cfg.General.Authentication = authentication
	cfg.Users = users
	authStore.Default.SetAuthenticator(auth.NewAuthenticator(users))
	if len(users) > 0 {
		// A loopback exemption would let any local app bypass the credentials.
		cfg.General.SkipAuthPrefixes = nil
		inbound.SetSkipAuthPrefixes(nil)
	}
}

func providerProxyDefinition(pdName, wantName string) map[string]any {
	raw, err := readRawConfig(runningConfigPath())
	if err != nil {
		return nil
	}
	declared, ok := raw.ProxyProvider[pdName]
	if !ok {
		return nil
	}
	mappings := providerDeclaredMappings(declared)
	exclude := providerRegexp(declared, "exclude-filter")
	filter := providerRegexp(declared, "filter")
	excludeTypes := providerExcludeTypes(declared)
	prefix, suffix, overrideFields := providerOverride(declared)
	for _, mapping := range mappings {
		name, _ := mapping["name"].(string)
		if name == "" {
			continue
		}
		if exclude != nil && exclude.MatchString(name) {
			continue
		}
		if filter != nil && !filter.MatchString(name) {
			continue
		}
		if shouldExcludeProxyType(mapping, excludeTypes) {
			continue
		}
		built := cloneStringAnyMap(mapping)
		builtName := prefix + name + suffix
		built["name"] = builtName
		for k, v := range overrideFields {
			built[k] = v
		}
		if builtName == wantName {
			return built
		}
	}
	return nil
}

func providerDeclaredMappings(declared map[string]any) []map[string]any {
	typeName, _ := declared["type"].(string)
	switch typeName {
	case "inline":
		return anySliceToStringAnyMaps(declared["payload"])
	case "file":
		path, _ := declared["path"].(string)
		if path == "" {
			return nil
		}
		if !filepath.IsAbs(path) {
			path = filepath.Join(filepath.Dir(runningConfigPath()), path)
		}
		buf, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		var schema struct {
			Proxies []map[string]any `yaml:"proxies"`
		}
		if err := yaml.Unmarshal(buf, &schema); err != nil {
			return nil
		}
		return schema.Proxies
	default:
		return nil
	}
}

func anySliceToStringAnyMaps(v any) []map[string]any {
	items, ok := v.([]any)
	if !ok {
		if typed, ok := v.([]map[string]any); ok {
			return typed
		}
		return nil
	}
	out := make([]map[string]any, 0, len(items))
	for _, item := range items {
		switch m := item.(type) {
		case map[string]any:
			out = append(out, m)
		case map[any]any:
			converted := make(map[string]any, len(m))
			for k, v := range m {
				ks, ok := k.(string)
				if !ok {
					continue
				}
				converted[ks] = v
			}
			out = append(out, converted)
		}
	}
	return out
}

func providerRegexp(declared map[string]any, key string) *regexp.Regexp {
	expr, _ := declared[key].(string)
	if expr == "" {
		return nil
	}
	re, err := regexp.Compile(expr)
	if err != nil {
		return nil
	}
	return re
}

func providerExcludeTypes(declared map[string]any) []string {
	raw, _ := declared["exclude-type"].(string)
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, "|")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}

func shouldExcludeProxyType(mapping map[string]any, excludeTypes []string) bool {
	if len(excludeTypes) == 0 {
		return false
	}
	t, _ := mapping["type"].(string)
	for _, exclude := range excludeTypes {
		if strings.EqualFold(t, exclude) {
			return true
		}
	}
	return false
}

func providerOverride(declared map[string]any) (prefix, suffix string, fields map[string]any) {
	fields = map[string]any{}
	override, ok := declared["override"].(map[string]any)
	if !ok {
		// try map[any]any
		if m, ok := declared["override"].(map[any]any); ok {
			override = make(map[string]any, len(m))
			for k, v := range m {
				if ks, ok := k.(string); ok {
					override[ks] = v
				}
			}
		} else {
			return "", "", fields
		}
	}
	prefix, _ = override["additional-prefix"].(string)
	suffix, _ = override["additional-suffix"].(string)
	for k, v := range override {
		switch k {
		case "additional-prefix", "additional-suffix":
			continue
		default:
			fields[k] = v
		}
	}
	return prefix, suffix, fields
}

func cloneStringAnyMap(in map[string]any) map[string]any {
	out := make(map[string]any, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}
