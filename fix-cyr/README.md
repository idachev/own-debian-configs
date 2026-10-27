# fix-cyr

Мигновена смяна ABC ↔ Bulgarian-Phonetic с клавиша Globe (🌐/Fn) на macOS.

## Защо

Вградената смяна на езика с Globe в macOS е бавна: системата изчаква отпускането на клавиша, показва popup/индикатор до курсора, а на macOS 26 и без това е лагава. `fix-cyr` слуша само Globe и сменя layout-а директно през `TISSelectInputSource` — за 0–8 ms.

## Как работи

- Globe натиснат и пуснат **сам** → смяна ABC ↔ Bulgarian-Phonetic.
- Globe + друг клавиш (Fn+F-клавиши, стрелки, Globe+E за емоджи) → игнорира се, работи както обикновено.
- Работи като LaunchAgent `com.mony.fixcyr`, стартира се сам при login.
- Ако няма разрешение Input Monitoring, иска го и се рестартира на ~10 s, докато не го получи.

## Инсталация

```
./install.sh
```

Скриптът:
1. компилира `bin/fix-cyr` (`swiftc`) и го подписва. Ако в keychain-а има сертификат за подпис с име, което завършва на `Local Signing`, ползва него. Иначе подписът е ad-hoc;
2. слага Globe на „Do Nothing“ (`AppleFnUsageType = 0`);
3. записва `~/Library/LaunchAgents/com.mony.fixcyr.plist` и стартира агента.

След това:
1. **System Settings → Privacy & Security → Input Monitoring** → включи `fix-cyr`.
2. **System Settings → Keyboard → „Press 🌐 key to“** → провери, че е **Do Nothing** (ако не е — избери го ръчно, `defaults write` не винаги се прилага веднага).
3. По желание скрий индикатора за език до курсора (важи след logout):
   ```
   defaults write kCFPreferencesAnyApplication TSMLanguageIndicatorEnabled 0
   ```

## Режим Caps Lock

```
./install.sh --capslock --layout-a com.apple.keylayout.US
```

- Caps Lock става F18 и вече не включва главни букви. `fix-cyr` сменя езика при **натискане** на F18, без да чака пускането.
- `fix-cyr` поглъща F18 и никое приложение не го получава. Без това терминалът праща F18 като `ESC[32~`, а zsh вмъква `~` на реда. За поглъщането трябва разрешение **Accessibility**, освен Input Monitoring.
- Ако има Karabiner-Elements, скриптът добавя `caps_lock → f18` в `simple_modifications` на активния профил. Преди това прави backup на `~/.config/karabiner/karabiner.json` до самия файл.
- Без Karabiner агентът прилага `hidutil` (Caps Lock → F18) при всяко стартиране, защото `hidutil` се губи след рестарт. ⚠️ Това заменя всички други `hidutil` пренасочвания, а `uninstall.sh` ги нулира.
- Повторно `install.sh` в другия режим първо пуска `uninstall.sh`, така че от стария режим не остава нищо.
- Изключи вградената смяна: System Settings → Keyboard → Input Sources → „Use Caps Lock to switch…“.
- `--layout-a` / `--layout-b` работят и в режим Globe. По подразбиране са `ABC` и `Bulgarian-Phonetic`.

В лога всяка смяна пише две времена: `select` (само смяната) и `key to done` (от натискането на клавиша до готовата смяна).

### Пример: Caps Lock + U.S. + Karabiner (macOS 26)

Setup с Caps Lock за смяна, U.S. вместо ABC и вече инсталиран Karabiner-Elements 16:

1. Провери кои layout-и са включени. Тук са `U.S.` и `Bulgarian - Phonetic`, без `ABC`:
   ```
   defaults read com.apple.HIToolbox AppleEnabledInputSources
   ```
2. Инсталирай:
   ```
   ./install.sh --capslock --layout-a com.apple.keylayout.US
   ```
3. Privacy & Security → Input Monitoring и Privacy & Security → Accessibility → включи `fix-cyr` и в двата списъка. Агентът се рестартира сам до ~10 s.
4. Keyboard → Input Sources → изключи „Use Caps Lock to switch…“.
5. Провери лога:
   ```
   tail -n 20 /tmp/fix-cyr.log
   ```
   Очаквано: `started key=f18 layouts=com.apple.keylayout.US,com.apple.keylayout.Bulgarian-Phonetic listen access=true accessibility=true`, после по един ред `toggle -> …` за всяко натискане.

Измерено: `key to done` е 2–22 ms. Karabiner и event tap-ът добавят 0.2–0.6 ms. Останалото е самата системна смяна (`TISSelectInputSource`). Вградената смяна с Caps Lock е бавна, защото чака пускането на клавиша, за да различи кратко натискане от задържане.

Правилото в Karabiner се вижда в Karabiner-Elements → Simple Modifications като `caps_lock → f18`. Не го махай ръчно, а през `./uninstall.sh`.

## Премахване

```
./uninstall.sh
```

Спира агента и трие plist-а. В режим Globe връща Globe на „Change Input Source“. В режим Caps Lock маха правилото от Karabiner или нулира `hidutil`.

## Проблеми

| Симптом | Причина / решение |
|---|---|
| Globe не прави нищо | Няма Input Monitoring разрешение. В лога: `listen access=false`. Включи `fix-cyr` (или off → on). |
| Езикът „мига“ и се връща / пак е бавно с popup | Системата също сменя с Globe → двойна смяна. Сложи ръчно Keyboard → „Press 🌐 key to: Do Nothing“. |
| Caps Lock не прави нищо | Няма Input Monitoring или Accessibility. В лога: `listen access=false` или `accessibility=false`. Включи `fix-cyr` и в двата списъка (или off → on). |
| В терминала Caps Lock пише `~` | Работи стар бинарник, който само слуша F18 и не го поглъща. Пусни отново `./install.sh --capslock …`. |
| Спря да работи след rebuild | Подписът е ad-hoc: новият бинарник има нов hash и macOS губи разрешенията. Махни и добави `fix-cyr` в Input Monitoring (и в Accessibility в режим Caps Lock). Със сертификат `… Local Signing` разрешенията остават. |

Лог: `/tmp/fix-cyr.log`. Статус: `launchctl print gui/$(id -u)/com.mony.fixcyr | grep state`.

## Други езици

Подай `--layout-a` / `--layout-b` на `install.sh`. Наличните ID-та:

```
defaults read com.apple.HIToolbox AppleEnabledInputSources
```
