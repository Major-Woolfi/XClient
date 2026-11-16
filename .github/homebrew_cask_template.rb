cask "XClient" do
  version "VERSION"

  on_macos do
    arch arm: "arm64", intel: "amd64"

    sha256 arm:   "ARM_SHA256",
           intel: "AMD_SHA256"

    url "https://github.com/Major-Woolfi/XClient/releases/download/v#{version}/XClient-#{version}-macos-#{arch}.dmg"
  end

  name "XClient"
  desc "Multi-platform proxy client based on ClashMeta"
  homepage "https://github.com/Major-Woolfi/XClient"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on :macos

  app "XClient.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-rd", "com.apple.quarantine", "{{appdir}}/XClient.app"],
        writable_paths: ["XClient.app"],
        writable_base:  :appdir
  end

  uninstall quit: "com.xclient"

  zap trash: [
    "~/Library/Application Support/com.xclient",
    "~/Library/Caches/com.xclient",
    "~/Library/Preferences/com.xclient.plist",
    "~/Library/Saved Application State/com.xclient.savedState",
  ]
end


