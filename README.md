# Skebobs

Roblox-игра про автомат с клешнёй: кейк-попсы, Скебобсы, базы, Патроны, погода, обмен и магазин Антона.
Весь код живёт здесь, карта и модели живут в плейсе (Team Create).

## Структура

```
src/shared/   -> ReplicatedStorage.Shared          (конфиг, формулы, Remotes, Achievements)
src/server/   -> ServerScriptService.Server        (Main.server.lua + Services/*)
src/client/   -> StarterPlayerScripts.Client       (HUD, контроллеры, UI/*)
build/        -> project-файлы Rojo и собранные .rbxm / тестовый плейс
tests/        -> Lune-тесты: формулы, цены, серверный и UI смоук
```

Порядок запуска сервисов задан в `src/server/Main.server.lua`.
Все числа баланса в `src/shared/Config/Balance.lua`, все тексты в `src/shared/Config/Strings.lua`.

## Работа с кодом через Rojo (Studio + GitHub)

1. Поставь инструменты: [Rokit](https://github.com/rojo-rbx/rokit), затем в папке репозитория `rokit install`
   (ставит Rojo, StyLua и Lune версий из `rokit.toml`).
2. В Studio поставь плагин Rojo: `rojo plugin install` или через Toolbox.
3. Открой плейс в Studio, в папке репозитория запусти `rojo serve`, в плагине нажми **Connect**.
   Код из `src/` подтянется в ReplicatedStorage.Shared, ServerScriptService.Server и
   StarterPlayerScripts.Client. Карту Rojo не трогает.
4. Правь код в редакторе, Studio обновляется сама. В конце **Save to Roblox (Ctrl+Alt+S)**.

Скрипты в Studio при подключённом Rojo править не нужно: при следующем `serve` они перезапишутся кодом из репозитория.

## Без Rojo

Собранные файлы лежат в `build/` (их же собирает CI на каждый коммит):
`Shared.rbxm` в ReplicatedStorage, `Server.rbxm` в ServerScriptService, `Client.rbxm` в StarterPlayerScripts.

## Тесты и сборка

```
stylua src tests
rojo build build/test_place.project.json -o build/Skebobs_test_place.rbxl
lune run tests/run.luau
lune run tests/prices.luau
lune run tests/server_smoke.luau build/Skebobs_test_place.rbxl
lune run tests/ui_smoke.luau build/Skebobs_test_place.rbxl
```

GitHub Actions (`.github/workflows/ci.yml`) делает то же самое на каждый push и прикладывает сборку артефактом.

## Тестовые клавиши в Studio

| Клавиша | Действие |
|---|---|
| B | Рюкзак |
| K | +монеты |
| F | попс в руки / бросить |
| G | попс рядом |
| P | тестовые Скебобсы |
| T | оглушение |
| Y | чужой попс |
| U | быстрый АФК |
| O | быстрый шкаф |
| N | семейство целиком |
| J | следующее погодное событие |

Прогресс в Studio сохраняется только если в Game Settings > Security включён **Enable Studio Access to API Services**.
