<p align="center"><img src="assets/yaro-banner.png" alt="Yaro — Windows 11, distilled" width="100%"></p>

# Yaro — облегчённая Windows 11 из официального образа

[English](README.md) | **Русский**

Yaro превращает чистую установку **официальной** Windows 11 в лёгкую, тихую и быструю систему:
без рекламы и предустановленного мусора, с минимумом телеметрии и фоновых служб, с настройками
для игр и разработки (Python, WSL2, Docker).

В репозитории **нет файлов Windows**. Windows скачивается с сайта Microsoft, а Yaro — это только
файл ответов (`autounattend.xml`) и скрипты PowerShell, которые вносят изменения при установке.

> [!WARNING]
> По умолчанию Yaro **отключает Microsoft Defender, SmartScreen, окна UAC, автообновления,
> печать, микрофон Bluetooth-гарнитур и встроенный VPN**. Прочитай раздел
> [Что Yaro отключает](#что-yaro-отключает) и [Опции](#опции) до установки.
> Сначала попробуй в виртуальной машине. Используешь на свой риск.

## Файлы

| Файл | Что это |
|---|---|
| `autounattend.xml` | Файл ответов для чистой установки. Скрипты вшиты внутрь. |
| `Yaro-Apply.cmd` | Применяет Yaro к уже установленной Windows 11. |
| `scripts/Specialize.ps1` | Системные изменения: приложения, компоненты, службы, реестр. |
| `scripts/FirstLogon.ps1` | Настройки пользователя и схема питания. |
| `scripts/YaroCommon.ps1` | Общие опции и запись в реестр для обоих этапов. |
| `scripts/SetWallpaper.ps1` | Ставит обои Yaro на рабочий стол. |
| `assets/` | Баннер, логотип, превью для GitHub и обои 1920×1080 «тетрадный лист»: светлые (белые, бежевые, жёлтые, в клетку, реалистичная бумага) и тёмные (ночное небо, слива, океан, лес, какао, тёмно-синие, графит, чёрные в клетку, реалистичная чёрная бумага). |

## Чистая установка (рекомендуется)

1. **Скачай Windows 11** с [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11):
   *Download Windows 11 Disk Image (ISO) for x64 devices*, язык **English (United States)**.
   Для образа на другом языке замени `en-US` на его код (например, `ru-RU`) в строках
   `UILanguage`, `SystemLocale` и `UserLocale` файла `autounattend.xml`.
2. **По желанию** открой `autounattend.xml` в Блокноте и поменяй:
   - `<TimeZone>UTC</TimeZone>` — свой часовой пояс, например `FLE Standard Time` (Киев, София),
     `Russian Standard Time` (Москва), `Central European Standard Time` (Варшава);
   - `<Name>User</Name>` — имя локальной учётной записи;
   - [опции](#опции) (найди строку `Yaro options`).
3. **Запиши флешку** (от 8 ГБ) программой [Rufus](https://rufus.ie): схема разделов **GPT**,
   целевая система **UEFI**. Когда Rufus покажет окно *Windows User Experience*, **сними все
   галочки**. Потом скопируй `autounattend.xml` в **корень** флешки.
4. **Загрузись с флешки.** Установщик спросит только диск или раздел — выбирай внимательно,
   данные на форматируемом разделе будут стёрты. Остальное пройдёт само, компьютер несколько
   раз перезагрузится.
5. **После первого входа:**
   - поставь драйверы (чипсет, видеокарта, Wi-Fi) с сайта производителя — Yaro отключает
     загрузку драйверов через Windows Update, поэтому драйвер Wi-Fi или сетевой карты лучше
     заранее положить на флешку;
   - загляни в журналы `%SystemRoot%\Setup\Scripts\Yaro\` — строки с `FAIL` показывают, что
     не применилось;
   - после драйверов Intel можно ещё раз запустить `Yaro-Apply.cmd`: он уберёт телеметрию,
     которую ставит ПО Intel.
6. **Активируй Windows своим ключом:** Settings › System › Activation › Change product key.
   Ключ в `autounattend.xml` — это общий *установочный* ключ Microsoft: он только выбирает
   редакцию **Pro** и не активирует систему. Для лицензии Home замени его на общий ключ Home
   `YTMG3-N6DKC-DKB77-7M9GH-8HVX7`.

## Применить к уже установленной Windows

1. *Code › Download ZIP*, распакуй архив.
2. Если хочешь выключить Defender, сначала отключи **Tamper Protection**
   (Безопасность Windows › Защита от вирусов и угроз › Управление настройками).
3. Запусти `Yaro-Apply.cmd` из учётной записи, которую хочешь настроить. Подтверди права
   администратора для системных изменений и точки восстановления. Параметры рабочего стола
   и приложений применяются к исходному пользователю, даже если пароль ввёл другой администратор.
4. Перезагрузи компьютер.

## Опции

Для чистой установки открой блок `Yaro options` в `autounattend.xml`, для `Yaro-Apply.cmd`
они находятся в `scripts/YaroCommon.ps1`. `$true` применяет настройку Yaro, `$false`
пропускает её при этом запуске.

| Опция | Что делает `$true` |
|---|---|
| `$DisableDefender` | Отключает антивирус Microsoft Defender и прячет его значок |
| `$DisableSmartScreen` | Отключает SmartScreen для скачанных файлов и программ |
| `$SilentUAC` | Программы получают права администратора без окна подтверждения |
| `$PauseUpdates` | Без автообновлений, обновления на паузе до 2077 года |
| `$DisablePrinting` | Отключает службу печати |
| `$DisableBtHandsFree` | Отключает режим Hands-Free: наушники в играх не уходят в глухое моно, их микрофон не используется |
| `$DisableVPN` | Отключает RasMan/RasAuto (встроенный VPN Windows и dial-up) |
| `$SetWallpaper` | Ставит обои Yaro «бежевый тетрадный лист» всем пользователям. Картинка встроена в `autounattend.xml` и сохраняется в `%SystemRoot%\Web\Wallpaper\Yaro\`; сменить обои можно в любой момент в Параметрах › Персонализация |

## Что Yaro меняет

### Что Yaro отключает
- Microsoft Defender, SmartScreen, Smart App Control, окна UAC *(опции)*.
- Целостность памяти / VBS (изоляция ядра), автоматическое шифрование BitLocker.
- Автоматические обновления Windows и загрузку драйверов через Windows Update.
- Печать, Hands-Free для Bluetooth, встроенный VPN *(опции)*, входящий удалённый рабочий стол.
- Определение местоположения, телеметрию, историю активности, рекламу и предлагаемые
  приложения, Copilot, виджеты, Bing в поиске «Пуска», синхронизацию OneDrive, Game Bar
  и запись игр, телеметрию PowerShell и .NET CLI.

### Удалённые приложения
Xbox и Game Bar, Copilot, Bing Search, виджеты, Карты, Записки, Семья, Кино и ТВ, Камера,
Будильники и часы, Советы, Связь с телефоном, Teams, Clipchamp, Power Automate, Dev Home,
Центр отзывов, Solitaire, Новости, Погода, Cross Device, Edge Game Assist, Кортана, Office,
новый Outlook, To Do, Люди, Получить справку, Запись голоса, Быстрая помощь, старая панель
Intel Graphics.
**Оставлены:** Microsoft Store, App Installer (winget), Terminal, Блокнот, Paint, Калькулятор,
Ножницы, Фотографии, Media Player, Edge, кодеки. Всё удалённое можно вернуть из Microsoft Store.

### Удалённые компоненты
Распознавание лица Windows Hello, режим Internet Explorer, Запись действий, распознаватель
математических формул, старый Windows Media Player, рукописный ввод и распознавание речи,
факсы и сканирование, дополнительные обои. Выключены: SMB1, PowerShell 2.0, печать XPS,
рабочие папки, удалённое разностное сжатие (RDC), старые компоненты мультимедиа.
Перед включением .NET Framework 3.5 Yaro проверяет архитектуру и базовую сборку пакета на подключённом носителе.
Если для этой версии требуется отдельный установщик, его можно
установить вручную, если он нужен приложению. [Инструкция Microsoft](https://learn.microsoft.com/en-us/dotnet/framework/install/dotnet-35-windows-11)

### Службы
Отключены: DiagTrack, dmwappushservice, MapsBroker, RetailDemo, CDPSvc, CDPUserSvc, TermService,
WSAIFabricSvc, PcaSvc, InventorySvc, TrkWks (+ Spooler, PrintNotify, BTAGService, RasMan,
RasAuto и службы Defender при включённых опциях). Вручную: WerSvc, службы Xbox, RmSvc.
Автоматически: SysMain, DPS. При входе Windows пропускает создание экземпляра отключённой
CDPUserSvc, если используется стандартный шаблон этой службы. Отключены фоновые задания совместимости, CEIP, диагностики
дисков и WinSAT. Когда синхронизация OneDrive заблокирована, Yaro отключает штатное задание
отчётности при выключенных административных отчётах. При тех же условиях Yaro убирает штатные
записи автозапуска OneDrive из текущего и шаблонного профилей, если администратор не потребовал
автозапуск политикой. Обновления клиента выполняет отдельное задание.

### Производительность
- Группировка служб (меньше процессов `svchost.exe`), сжатие памяти включено.
- Ядро остаётся в ОЗУ, зарезервированное хранилище выключено. Энергопотреблением фоновых задач управляет Windows.
- Обновление времени последнего доступа NTFS выключено, разрешены длинные пути (> 260 символов).
  Создание коротких имён 8.3 определяется настройками Windows и администратора.
- Аппаратное планирование GPU. Оптимизация оконного режима и переменная частота обновления
  включаются при отсутствии соответствующих настроек. Существующий выбор сохраняется.
- Фоновая запись недавних игровых моментов Game Bar выключена для текущего и новых профилей.
  Game Mode задаётся параметрами Windows. Режим прерываний выбирает драйвер устройства.
- На схеме Balanced и совместимых с ней схемах Yaro выбирает *Best Performance* при питании от
  розетки. Режим от батареи сохраняется. Если *Best Performance* недоступен, Yaro пробует схему
  *Ultimate Performance* с минимумом CPU 5 %. Эта схема может расходовать больше заряда батареи.
  Ранее установленные глобальные параметры троттлинга и коротких имён сохраняют свои значения.
- Без сетевого ограничения для мультимедиа, Edge не загружается заранее в фоне.
- Установщики и драйверы не зависают на 2 минуты на проверке сертификатов
  (короткие таймауты загрузки сертификатов).

### Интерфейс
Тёмная тема, контекстное меню Windows 10, пункт *Open in Notepad* для любых файлов, *End task*
на панели задач, без кнопок поиска, представления задач, чата и Copilot, мгновенные меню,
папки в отдельном процессе, интерфейс на английском с раскладками English и Russian,
включён режим разработчика, на рабочем столе обои Yaro.

### Установка
Пропускаются проверки железа (TPM, Secure Boot, процессор, ОЗУ, диск). Нет экранов лицензии,
сети, учётной записи Microsoft и конфиденциальности; один локальный администратор `User`
без пароля; случайное имя компьютера.

## Как вернуть основные изменения

Выполни в **командной строке от администратора** и перезагрузись.

| Что | Команда |
|---|---|
| Печать | `sc config Spooler start= auto` и `sc config PrintNotify start= demand` |
| Микрофон Bluetooth-гарнитуры | `sc config BTAGService start= demand` |
| Встроенный VPN | `sc config RasMan start= demand` и `sc config RasAuto start= demand` |
| Окна UAC | `reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 5 /f` |
| Автообновления | `reg delete HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU /v NoAutoUpdate /f`, затем Settings › Windows Update › *Resume updates* |
| Контекстное меню Windows 11 | `reg delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f` |
| Удалённые приложения | Установить из Microsoft Store |

Defender и SmartScreen проще всего сохранить, поставив `$DisableDefender = $false` /
`$DisableSmartScreen = $false` **до** установки.

Если позже вернёшь синхронизацию OneDrive, задание отчётности можно включить в
Планировщике задач. Открой OneDrive и включи автозапуск в его настройках. Для нового профиля
при необходимости запусти штатный установщик OneDrive.

## Если что-то пошло не так

- **«Windows could not parse or process the unattend answer file»** — файл повредился при
  правке. Скачай его заново и повтори только нужные изменения.
- **Установка останавливается с ошибкой языка** — язык образа не совпадает с `en-US` в файле
  (см. шаг 1).
- **После установки нет интернета** — поставь сетевой драйвер с сайта производителя.
- **Что-то не применилось** — ищи `FAIL` в `%SystemRoot%\Setup\Scripts\Yaro\Specialize.log`
  и в журнале пользователя. Для уже установленной системы это `%LOCALAPPDATA%\Yaro\FirstLogon.log`.
  После чистой установки оба журнала находятся в системном каталоге.

## Обои

Обои «тетрадный лист», 1920×1080. Нажми на картинку, чтобы открыть её в полном размере, и сохрани.

**Светлые**

<table>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-paper-real.png"><img src="assets/yaro-wallpaper-paper-real.png" width="280" alt="реалистичная бумага"></a><br><sub>реалистичная бумага</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-white.png"><img src="assets/yaro-wallpaper-white.png" width="280" alt="белые"></a><br><sub>белые</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-cream.png"><img src="assets/yaro-wallpaper-cream.png" width="280" alt="бежевые"></a><br><sub>бежевые</sub></td>
</tr>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-yellow.png"><img src="assets/yaro-wallpaper-yellow.png" width="280" alt="жёлтые"></a><br><sub>жёлтые</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-grid.png"><img src="assets/yaro-wallpaper-grid.png" width="280" alt="в клетку"></a><br><sub>в клетку</sub></td>
<td></td>
</tr>
</table>

**Тёмные**

<table>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-night.png"><img src="assets/yaro-wallpaper-dark-night.png" width="280" alt="ночное небо"></a><br><sub>ночное небо</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-plum.png"><img src="assets/yaro-wallpaper-dark-plum.png" width="280" alt="слива"></a><br><sub>слива</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-ocean.png"><img src="assets/yaro-wallpaper-dark-ocean.png" width="280" alt="океан"></a><br><sub>океан</sub></td>
</tr>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-forest.png"><img src="assets/yaro-wallpaper-dark-forest.png" width="280" alt="лес"></a><br><sub>лес</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-cocoa.png"><img src="assets/yaro-wallpaper-dark-cocoa.png" width="280" alt="какао"></a><br><sub>какао</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-paper-real.png"><img src="assets/yaro-wallpaper-dark-paper-real.png" width="280" alt="реалистичная чёрная бумага"></a><br><sub>реалистичная чёрная бумага</sub></td>
</tr>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-navy.png"><img src="assets/yaro-wallpaper-dark-navy.png" width="280" alt="тёмно-синие"></a><br><sub>тёмно-синие</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-graphite.png"><img src="assets/yaro-wallpaper-dark-graphite.png" width="280" alt="графит"></a><br><sub>графит</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-grid.png"><img src="assets/yaro-wallpaper-dark-grid.png" width="280" alt="чёрные в клетку"></a><br><sub>чёрные в клетку</sub></td>
</tr>
</table>

## Примечания

- Yaro выросла из личной сборки Windows 11 автора, которой он пользуется каждый день на
  ноутбуке с Intel Core i7-9750H и GeForce RTX 2060. Вариант с файлом ответов для официального
  образа новый — проверь его в виртуальной машине (Hyper-V, VirtualBox), прежде чем ставить
  на основной компьютер.
- Проект не связан с Microsoft. Windows — товарный знак Microsoft Corporation.
  В репозитории нет программ Microsoft и средств активации.
- Лицензия: [MIT](LICENSE).
