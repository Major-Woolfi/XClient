# XClient

Кроссплатформенный VPN-клиент на базе **Clash.Meta** и **Xray-core**.
Windows · macOS · Linux · Android. Без рекламы, без трекинга, с открытым исходным кодом.

[![GitHub release](https://img.shields.io/github/v/release/Major-Woolfi/XClient?include_prereleases&label=Latest)](https://github.com/Major-Woolfi/XClient/releases/latest)
[![GitHub stars](https://img.shields.io/github/stars/Major-Woolfi/XClient)](https://github.com/Major-Woolfi/XClient/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Major-Woolfi/XClient)](https://github.com/Major-Woolfi/XClient/network/members)
[![GitHub issues](https://img.shields.io/github/issues/Major-Woolfi/XClient)](https://github.com/Major-Woolfi/XClient/issues)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Contributors](https://img.shields.io/github/contributors/Major-Woolfi/XClient)](https://github.com/Major-Woolfi/XClient/graphs/contributors)

---

## 📥 Скачать

Все релизы публикуются в этом же репозитории:

👉 **[Последний релиз на GitHub](https://github.com/Major-Woolfi/XClient/releases/latest)**

| Платформа | Файл |
| --------- | ---- |
| **Windows** | `XClient-Setup.exe` (инсталлятор) / `.zip` (портативная версия) |
| **macOS** | `.dmg` (Apple Silicon и Intel) |
| **Linux** | `.AppImage` / `.tar.gz` |
| **Android** | `.apk` |

После установки просто запустите приложение - дополнительная настройка не требуется.

---

## 🔥 Киллер-фичи

### Два ядра в одном приложении

**Clash.Meta** для привычных YAML-подписок и **Xray-core** для современных ссылок (vmess, vless, trojan, shadowsocks). Ядро выбирается автоматически по содержимому конфига - вам не нужно переключать его вручную.

### Импорт конфигов

- По ссылке: `clash://`, `clashmeta://`, `vmess://`, `vless://`, `trojan://`, `ss://`, `ssconf://`
- Из файла: YAML (Clash), JSON (Xray)
- По QR-коду и URL подписки
- Автообновление подписок

### Управление ядрами

Устанавливайте, переключайте и удаляйте версии ядер прямо в интерфейсе. Каждое ядро живёт в своей папке и обновляется независимо от приложения.

### Настройка Xray без кода

Графический конфигуратор Xray-core: порт прослушивания, уровень логов, DNS-серверы, правила маршрутизации и исходящие соединения - всё в удобной форме, без ручного редактирования.

### Конфиденциальность

Никакой телеметрии, никакой аналитики, никакой рекламы. Ваши серверы, ключи и подписки никуда не уходят с устройства.

### Другие возможности

- Поддержка нескольких языков интерфейса
- Трей и строка меню на десктопе (быстрое включение/выключение)
- TUN-режим на Android, Windows, macOS, Linux
- Тесты задержки до прокси-узлов
- Живые логи соединений и DNS-запросов
- Резервное копирование и восстановление профилей

---

## 📋 Поддерживаемые протоколы

`Clash` · `VLESS` · `VMess` · `Trojan` · `Shadowsocks` · `Hysteria2` · `SOCKS5` · `WireGuard`

---

## 🛠️ Быстрый старт

1. Скачайте установочный файл с [страницы релизов](https://github.com/Major-Woolfi/XClient/releases/latest).
2. Установите приложение.
3. Добавьте профиль по ссылке или через импорт файла.
4. Нажмите «Подключить».

---

## 🤝 Контрибьюция

Приветствуется любой вклад - от исправления опечаток до новых фичей.
Перед отправкой Pull Request прочтите [правила участия](CONTRIBUTING.md) и [кодекс поведения](CODE_OF_CONDUCT.md).

---

## 📄 Лицензия

Проект распространяется под лицензией **MIT**. Подробности в [LICENSE](LICENSE).

---

Сделано с ❤️ [Major Woolfi](https://github.com/Major-Woolfi)
