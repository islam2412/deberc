# Деберц

Карточная игра Деберц для iPhone и iPad — по нашим домашним правилам, против компьютера.

![Скриншоты с симулятора iPhone](docs/preview.png)

- 2 или 3 игрока (вы и 1–2 компьютерных соперника), партия до 701 очка.
- Торговля в два круга, «обязы», обмен козырной семёрки, четыре семёрки, терцы, полтинники, бэла.
- Байт, висячий байт, штрафы за байты и за «голого».
- Три уровня сложности, подсказка, запись партии, сохранение партии.
- Каждое правило можно переключить в настройках.

Полный свод правил — в [RULES.md](RULES.md).

## Устройство проекта

| Папка | Что внутри |
|---|---|
| `DebercKit/` | Swift-пакет: движок игры, подсчёт, ИИ, тексты. Не зависит от iOS, покрыт тестами. |
| `Deberc/` | Приложение на SwiftUI (iOS 17+, iPhone и iPad). |
| `Deberc.xcodeproj` | Проект Xcode (нужен Xcode 26 или новее). |
| `Config/Deberc.xcconfig` | Team ID, Bundle ID, версия и номер сборки. |
| `.github/workflows/` | CI (тесты, сборка, проверка на симуляторах) и загрузка в TestFlight. |
| `docs/` | Инструкции по TestFlight и тексты для App Store Connect. |

## Запуск на своём iPhone/iPad

1. Откройте `Deberc.xcodeproj` в Xcode 26+.
2. Выберите схему **Deberc** и своё устройство.
3. Во вкладке **Signing & Capabilities** выберите свою команду (Team) — или впишите Team ID в `Config/Deberc.xcconfig`.
4. Нажмите **Run** (⌘R).

## Тесты движка

```sh
cd DebercKit
swift test
```

Тесты работают и на Linux (достаточно Swift 5.9+).

## TestFlight

Пошаговая инструкция, как выложить приложение в публичный TestFlight: [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md).
Тексты для App Store Connect: [docs/APP_STORE_CONNECT.md](docs/APP_STORE_CONNECT.md).
Политика конфиденциальности: [PRIVACY.md](PRIVACY.md).
