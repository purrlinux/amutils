# amutils — дизайн-документ

Замена autils для Qwaderton Linux. Сборка пакетов, управление бинарными
репозиториями, разрешение зависимостей. Реализация — busybox-совместимый
POSIX sh.

> inspired by autils by emmett1

Автор: Atarwn Gard <atarwn@qwaderton.org>
Лицензия: **MIT** (намеренно не GPLv3: у autils лицензия совместимости
с идеями проекта нет, см. issue codeberg.org/emmett1/alicelinux про
`repos/core/autils/info`).

## 1. Принципы

1. **reposync — единая точка истины.** Никаких собственных форматов баз
   (APKGBINDB умирает). Метаданные пакета (имя, версия, зависимости,
   описание, скрипты) читаются напрямую из синхронизированных git-репо
   с рецептами. amu-src и amu-bin смотрят в одни и те же данные.
2. **amu-bin — единственный, кто работает с пакетами и spm.**
   Установка, обновление, удаление, запросы к pkgdb, запуск pre/postinstall
   и триггеров, упаковка fakeroot в `.spm` (`spm -b`) — всё это делает
   только amu-bin. `amu-src` собирает и **делегирует установку amu-bin**.
   Роутер `amu` к spm не обращается вообще. Весь системно-мутирующий
   трафик идёт через один инструмент.
3. **Одна библиотека, а не копипаста.** Общий код (msg/die, поиск
   рецептов, чтение зависимостей, чтение pkgdb, версии) живёт в
   `libam.sh`. Функции, трогающие spm, живут внутри amu-bin.
4. **Пакетный менеджер ≠ системные утилиты.** `amu*` — только пакеты.
   `reposync`, `updateconf`, `genfstab`, `qlchroot` — отдельные
   самостоятельные инструменты без зависимости от библиотеки amu.
5. **Совместимость рецептов.** Формат `abuild`, файлы `depends`,
   `makedepends`, `info`, `preinstall`, `postinstall`, `.shasum`,
   `.files` — без изменений, чтобы репозиторий `core/` продолжил
   работать как есть.
6. **busybox sh.** Никаких bashизмов. Проверка: `busybox sh -n` +
   запуск под busybox в qlchroot.
7. **MIT, минимум комментариев в коде.**

## 2. Состав и дерево файлов

```
amutils/
├── Makefile
├── LICENSE                 (MIT)
├── README.md
├── lib/
│   └── libam.sh            общая библиотека (не исполняемый файл)
├── bin/
│   ├── amu                 роутер/фасад
│   ├── amu-src             сборка из исходников (makepkg-роль)
│   ├── amu-bin             пакетный менеджер (единственный пользователь spm)
│   ├── amu-resolv          разрешение зависимостей
│   ├── amu-trigger         пост-установочные триггеры (вызывается amu-bin)
│   ├── reposync            синхронизация git-репозиториев
│   ├── updateconf          мерж .new конфигов
│   ├── genfstab            генерация fstab из смонтированной системы
│   └── qlchroot            chroot с бинд-маунтами
├── doc/
│   ├── design.md           этот документ
│   ├── amu.conf.example
│   ├── recipe.md           формат рецепта
│   └── buildopts.md        флаги автодетектируемых сборочных систем
└── man/
    ├── amu.8  amu-src.8  amu-bin.8  amu-resolv.8  amu-trigger.8
    ├── reposync.8  updateconf.8  genfstab.8  qlchroot.8
```

Хелперы autils — не отдельные бинарники, а **подкоманды `amu`** (§9).

## 3. Общая библиотека `libam.sh`

Каждый инструмент `amu*` начинается с:

```sh
#!/bin/sh
. "${AMU_LIB:-/usr/lib/amu/libam.sh}"
```

(шапка файлов — отдельно: `(C) 2026 Atarwn Gard <atarwn@qwaderton.org>`,
`inspired by autils by emmett1`, лицензия MIT)

Поиск библиотеки: переменная `AMU_LIB`, иначе фиксированный путь
установки `$(PREFIX)/lib/amu/libam.sh`. Запуск из дерева исходников —
`AMU_LIB=$PWD/lib/libam.sh`.

### 3.1. Конфигурация и переменные

`libam.sh` читает `/etc/amu.conf` (sourcing), если не задан
`AMU_NOCONF=1`. Преемники APKG_*:

| Переменная | Дефолт | Назначение |
|---|---|---|
| `AMU_REPO` | — | список каталогов с рецептами (первый найденный выигрывает) |
| `AMU_PACKAGE_DIR` | `$PWD` | куда складывать собранные `.spm` |
| `AMU_SOURCE_DIR` | `$PWD` | кэш исходных тарболов |
| `AMU_WORK_DIR` | `$PWD` | рабочее дерево сборки |
| `AMU_ROOT` | `/` | альтернативный корень установки |
| `AMU_BINREPO` | — | URL бинарного репозитория (http/https/ftp) или локальный путь |
| `AMU_CACHE_DIR` | — | кэш скачанных `.spm` (обязателен для amu-bin) |
| `AMU_NOPROMPT` | — | не спрашивать подтверждение |
| `AMU_KEEP_WORKDIR` | — | не удалять дерево сборки при ошибке |
| `AMU_ALIAS` | — | подстановка зависимостей `real:alias` |
| `AMU_MASK` | — | пакеты, пропускаемые при `-U` |
| `AMU_STRICT` | — | падать, если у бинарного пакета нет `.sha3` |
| `AMU_LOG`, `AMU_LOG_DIR` | — | логирование сборки |
| `AMU_SHA` | `b3sum` | контрольные суммы. **Отступление от autils**: тот хардкодил `sha3sum`, которого нет в core (только `b3sum`, BLAKE3) — checksums в autils молча были пустыми. Дефолт — `b3sum`, переопределяется. Файлы по-прежнему `.shasum`/`.spm.sha3` (содержимое — хеш от $AMU_SHA) |

### 3.2. Функции библиотеки

Общие:

- `amu_msg`, `amu_die`, `amu_needroot`, `amu_prompt`.
- `amu_list_has <list> <item>` — замена идиомы `printf | tr | grep -Fxq`.
- `amu_ver_eq <a> <b>`; разбор `name#version-release` в одном месте.

pkgdb (только чтение, файлы):

- `amu_pkgdb` — `${AMU_ROOT%/}/var/lib/spm/db`.
- `amu_is_installed <name>`, `amu_installed_ver <name>`.

Репозитории рецептов:

- `amu_recipe_dir <pkg>` — первый `$r/$pkg` с файлом `abuild`.
- `amu_recipe_meta <pkg>` — напечатать `name version release` из abuild.
- `amu_recipe_deps <pkg> [make]` — зависимости из `depends`/`makedepends`
  с `AMU_ALIAS`, одна на строку.
- `amu_recipe_field <pkg> <key>` — поля из `info`.

Всё, что вызывает spm (обёртки `amu_spm`, установка/удаление/упаковка,
pre/postinstall, вызов `amu-trigger`), — **внутри amu-bin**, не в lib.

## 4. Бинарный репозиторий

- **Истина** — git-репо с рецептами, синхронизируемые `reposync`.
- **Дистрибуция** — HTTP-сервер (или локальный каталог) с готовыми
  `.spm`. Никакой базы данных: имя файла формируется из истины.

```
$AMU_BINREPO/
  name#version-release.spm        пакет
  name#version-release.spm.sha3   контрольная сумма (sidecar)
```

URL: `$AMU_BINREPO/` + URL-encoded (`#` → `%23`) имя файла.
Публикация: `for p in *.spm; do sha3sum "$p" | awk '{print $1}' > "$p.sha3"; done`.

Проверка: sidecar есть — сверяем, несовпадение = смерть. Нет sidecar —
предупреждение (смерть при `AMU_STRICT=1`).

## 5. amu-resolv

Единый резолвер, один бэкенд — репозитории рецептов. Бинарного
бэкенда нет: amu-bin резолвит по тем же рецептам.

```
amu-resolv -d <pkg>        прямые зависимости
amu-resolv -dd <pkg>       прямые + makedepends
amu-resolv -D <pkg...>     полное замыкание в порядке установки
amu-resolv -DD <pkg...>    то же + makedepends
amu-resolv -j <pkg>        прямые зависенты
amu-resolv -jj <pkg>       зависенты + makedepends
```

DFS с защитой от циклов (порт логики apkg-resolv поверх libam).
Переменные: `AMU_REPO`, `AMU_RESOLV_SKIP_INSTALLED`, `AMU_ALIAS`,
pkgdb через `AMU_ROOT`.

## 6. amu-src

Роль makepkg. **Систему не трогает**: собирает `.spm` и делегирует
установку `amu-bin`.

```
amu-src                    собрать рецепт из текущего каталога
amu-src -i [pkg...]        собрать и установить (через amu-bin)
amu-src -u [pkg...]        пересобрать и обновить (через amu-bin)
amu-src -f                 принудительная пересборка
amu-src -w [pkg...]        только скачать исходники
amu-src -p <pkg...>        путь к рецепту
amu-src -g [pkg...]        перегенерировать .shasum
amu-src -k [pkg...]        перегенерировать .files
amu-src -s [pattern]       поиск по репозиториям
amu-src -v                 verbose (для -s)
amu-src -h
```

- Поиск рецептов/метаданных — через libam.
- Установочный путь: собрать пакет → `amu-bin -i <файл.spm>` (или
  `amu-bin -u`). preinstall гоняется до сборки (как в autils),
  postinstall и триггеры — уже на стороне amu-bin.
- Упаковка fakeroot в `.spm`: `amu-src` вызывает `amu-bin -b`
  (обёртку над `spm -b`), чтобы spm дёргался только из amu-bin.
- Автодетект сборочных систем: тот же порядок (meson/muon → configure →
  cmake → setup.py → Makefile.PL → Makefile), те же флаги
  (`doc/buildopts.md`), те же переменные рецепта (`build_opt`,
  `build_type`, `build_dir`, `sv`, `skip_patch`, `patch_opt`,
  `keep_*`, `no_strip`, хуки `build`/`prebuild`/`postbuild`,
  `safely_rebuildable`, `rebuild`).
- Постобработка (gzip man/info, удаление `*.a`/`*.la`/locale/doc,
  strip ELF, runit-сервисы) — без изменений.
- `AMU_LOG`/`AMU_LOG_DIR` — логирование сборки (в autils заявлено,
  не реализовано; здесь реализуется).

## 7. amu-bin

Пакетный менеджер. **Единственный пользователь spm.** Источник
истины — рецепты, дистрибуция — `$AMU_BINREPO`.

```
amu-bin -i <файл.spm | имя...>   установить файл или скачать по имени
                                 (с разрешением зависимостей для имён)
amu-bin -u <файл.spm | имя...>   обновить/переустановить
amu-bin -r <имя...>              удалить (простое удаление, как spm -r)
amu-bin -R <имя...>              удалить вместе с ставшими ненужными зависимостями
amu-bin -U                       полное обновление системы
amu-bin -o <имя...>              только скачать в кэш
amu-bin -c                       чистить кэш от битых .spm
amu-bin -Q [pattern]             список установленных (опц. фильтр)
amu-bin -l <pkg>                 список файлов установленного пакета
amu-bin -O <file>                владелец файла
amu-bin -s [pattern]             поиск доступных пакетов (по рецептам)
amu-bin -b                       упаковать cwd (fakeroot) в .spm — для amu-src
amu-bin -v, -h
```

Потоки:

- **-i**: аргумент — существующий файл → прямая установка (preinstall
  → spm -i → postinstall → amu-trigger). Имя → замыкание зависимостей
  через `amu-resolv -D` (со SKIP_INSTALLED) → для каждого: версия из
  рецепта → скачать → проверить `.sha3` → установить. Подтверждение
  списком.
- **-u**: файл → spm -u; имя → версия из рецепта, отлична от
  установленной (или равна — переустановка) → скачать → обновить.
- **-r**: прямое удаление через spm -r, без анализа зависимостей
  (простая команда, которой не хватало apkg-bin).
- **-R**: умное удаление: замыкание целей, пропуск целей с внешними
  установленными зависентами, удаление ставших ненужными зависимостей
  (одна реализация для -R, `amu purge`, `amu orphan`).
- **-U**: устаревшие = установленные, версия в рецепте отличается
  (минус `AMU_MASK`) → замыкание → сначала новые, потом апгрейды.
- **-c**: сверить кэш с `.sha3`, удалить несовпадающие.
- **-Q/-l/-O**: чтение pkgdb через spm (пользователь напрямую с spm
  больше не работает).

Что исчезает: `bin_generate`/`-g`/`-S` (APKGBINDB), base64-скрипты,
двойной бэкенд резолвера. Вместо `-S` — `reposync`.

## 8. amu-trigger

Системное обслуживание после установки (отдельный инструмент,
вызываемый из amu-bin):

```
amu-trigger [pkg...]    прогнать триггеры (по умолчанию все установленные)
```

11 триггеров из apkg-src: mimedb, desktopdb, fontcache, fccache,
udevdb, iconcache, gtk3immodules, gtk2immodules, glibschema,
giomodules, gdkpixbufcache. Каждый проверяет наличие команды и
релевантных файлов пакета (через `amu-bin -l`).

## 9. Роутер amu

Чистый роутер, `exec`-делегирует, сам ничего не делает, к spm не
обращается:

```
amu -i/-u [цель...]    контекстная маршрутизация (см. ниже)
amu -r/-R/-U/-o/-c     → amu-bin
amu -Q/-l/-O/-s        → amu-bin
amu -w/-p/-g/-k        → amu-src
amu -d/-dd/-D/-DD/-j/-jj → amu-resolv
```

**Контекст для -i/-u** (главное отличие от autils): роутер смотрит
на аргументы и решает, строить из исходников или ставить бинарник:

- аргумент — существующий `.spm` файл → `amu-bin -i/-u файл`;
- аргумент — имя, для которого есть рецепт в `AMU_REPO` →
  `amu-src -i/-u имя` (собрать и поставить);
- аргумент — имя без рецепта → `amu-bin -i/-u имя` (скачать);
- без аргументов + `./abuild` → `amu-src` (сборка текущего рецепта).

Подкоманды (хелперы autils, переехавшие внутрь amu; реализованы как
функции libam, при необходимости удаления вызывают `amu-bin -r/-R` —
не spm):

```
amu trigger [pkg...]           → amu-trigger
amu purge [--do-it] <pkg...>   план удаления pkg + ненужных зависимостей
amu orphan                     установленные пакеты без зависентов
amu foreign                    установленные пакеты вне репозиториев
amu mdpurge [--do-it] [pkg...] сиротские makedepends
amu clean [-p|-s]              устаревшие .spm/исходники в stdout (под xargs rm)
amu deps <pkg>                 ldd-анализ реальных зависимостей
amu redundantdeps [-f] [pkg]   транзитивные зависимости в depends
amu genabuild <url> [name]     шаблон рецепта
amu revdep [-v]                битые ELF-связи после апгрейда
```

Вызов без аргументов в каталоге с `abuild` — сборка (как в autils).

## 10. Системные утилиты

Без зависимости от libam, без префикса amu.

### reposync

Env-driven синхронизация git-репо, `REPOSYNC_<name>='url|branch|path'`.
Флаги `-n` (dry-run), `-l` (лог), `-f` (force). Отличия от autils:
убран `eval`, `git clean -fdx` только внутри известных путей репо.

### updateconf

Мерж `.new` файлов. Фиксы: используется `$EDITOR` (не хардкод vim),
цель аргументом (`updateconf [dir]`, дефолт `/etc`), уважает
`AMU_ROOT`. Цикл U/D/E/K без изменений.

### genfstab (новый)

```
genfstab [-U|-L|-s] <root>
  -U   UUID через blkid (дефолт)
  -L   метки через blkid
  -s   печатать псевдо-fs (proc/sysfs/devpts/tmpfs) явно
```

Источник — `/proc/self/mounts`; `/dev/*` → `UUID=`/`LABEL=`, bind →
`none ... bind`, точки вне `<root>` пропускаются.

### qlchroot

`qlchroot [-k] <dir> [cmd...]`. Бинд-маунты /dev, /dev/pts, /proc,
/sys, /run (tmpfs), efivars на EFI; resolv.conf с бэкапом; `env -i`
внутри. `-k` — не размонтировать при выходе.

## 11. Установка

Makefile: `bin/*` → `$(PREFIX)/bin/`, `lib/libam.sh` →
`$(PREFIX)/lib/amu/libam.sh`, `man/*.8` → `$(PREFIX)/share/man/man8/`.
Оверрайды `DESTDIR`, `PREFIX`, `BINDIR`, `LIBDIR`, `MANDIR`.

## 12. Миграция с autils

| autils | amutils |
|---|---|
| `apkg` | `amu` |
| `apkg-src` | `amu-src` |
| `apkg-bin` (+APKGBINDB) | `amu-bin` (рецепты + `.spm.sha3`) |
| `apkg-resolv` | `amu-resolv` |
| триггеры в apkg-src | `amu-trigger` |
| `apkg-purge` | `amu purge` |
| `apkg-orphan` | `amu orphan` |
| `apkg-foreign` | `amu foreign` |
| `apkg-mdpurge` | `amu mdpurge` |
| `apkg-clean` | `amu clean` |
| `apkg-deps` | `amu deps` |
| `apkg-redundantdeps` | `amu redundantdeps` |
| `apkg-genabuild` | `amu genabuild` |
| `revdep` | `amu revdep` |
| `apkg-chroot` | `qlchroot` |
| `updateconf` | `updateconf` (fixed) |
| `reposync` | `reposync` (fixed) |
| — | `genfstab` (новый) |
| `/etc/apkg.conf`, `APKG_*` | `/etc/amu.conf`, `AMU_*` |

Репозиторий `core/` и формат рецептов не меняются.

## 13. Этапы реализации

1. man-страницы (интерфейс зафиксирован здесь) — **готово**.
2. `libam.sh` + `amu-resolv` — **готово**.
3. `amu-src` — **готово**.
4. `amu-bin` + `amu-trigger` — **готово**.
5. `amu` (роутер + подкоманды) — **готово**.
6. `reposync`, `updateconf`, `genfstab`, `qlchroot` — **готово**.
7. Makefile, LICENSE (MIT), README, пример конфига — **готово**.

Проверено: `sh -n` + `busybox sh -n` (чисто), рендер man без
предупреждений, `make install DESTDIR=...` (чисто), смоук-тест с
поддельным pkgdb/spm: resolv (-d/-D/-DD/-j, alias), роутинг (файл →
amu-bin, имя с рецептом → amu-src, без рецепта → amu-bin), установка по
имени с замыканием зависимостей и проверкой `.sha3`, `-r` (отказ при
зависентах), `-R`/purge (порядок удаления), `mdpurge`, `orphan`,
`foreign`, `clean`, `genabuild`, сборка мета-пакета через `amu-src`
(включая делегирование `amu-bin -b` и установку), `genfstab`, `reposync
-n`.

Найдено и исправлено относительно autils по ходу: `muon_build` вызывал
`meson setup` (сборка шла через samu/muon); хардкод `sha3sum` при
отсутствии его в core (→ `AMU_SHA`, дефолт `b3sum`, явная ошибка при
отсутствии); `case`-глоб `*` не матчит `\n` (lists нормализуются);
`amu_die` внутри `$(...)` убивает только сабшелл (все внешние вызовы
получили `|| continue`/`|| exit 1`); рекурсия amu-src по имени пакета
должна передавать только флаги.
