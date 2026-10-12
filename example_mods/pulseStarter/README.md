# Pulse Starter

この例はEnhanced Funkinの安全な宣言型スクリプト形式「FunkPulse」を使います。既存のPolymod/HScriptを置き換えるものではなく、簡単な処理を公式のHScriptコールバック名・プロパティ名に近い形で書くための薄い互換レイヤーです。

```text
pulseStarter/
├── _polymod_meta.json  # 現行Mod Menu互換メタデータ
├── pulse.json          # FunkPulse manifest
└── logic/
    ├── main.pulse      # FunkPulse DSL
    └── extra.pulse     # main.pulseから起動される別ファイル
```

このフォルダをゲームの `mods/` ディレクトリへコピーすると、通常のMod Menuから有効／無効を切り替えられます。`pulse.json` の `id` はフォルダ名と一致させてください。

## スクリプト構文

公式のHScriptで使うイベント名に近い `onBeatHit` / `onStepHit` と、カメラ・体力のプロパティに近い命令を使えます。

```text
onBeatHit 8 -> setProperty camGame.zoom 1.05
onStepHit 32 -> setProperty camHUD.zoom 1.02
onBeatHit 16 -> addHealth -0.10
onBeatHit 24 -> setHealth 1.00
onBeatHit 32 -> emit.ZoomCamera 1.10
onBeatHit 40 -> emit.ScrollSpeed 1.25
```

利用できる命令は次の通りです。

- `onBeatHit N -> setProperty camGame.zoom VALUE`
- `onStepHit N -> setProperty camHUD.zoom VALUE`
- `onBeatHit N -> addHealth VALUE`
- `onBeatHit N -> setHealth VALUE`
- `onBeatHit N -> emit.ZoomCamera VALUE`
- `onBeatHit N -> emit.ScrollSpeed VALUE`
- `onBeatHit N -> emit.SetCameraBop VALUE`
- `onBeatHit N -> emit.SetTargetBopSpeed VALUE`
- `onBeatHit N -> emit.FocusCamera VALUE`（0=プレイヤー、1=相手、2=GF）
- `onBeatHit N -> setScrollSpeed VALUE`
- `onBeatHit N -> setPlayerScrollSpeed VALUE`
- `onBeatHit N -> setOpponentScrollSpeed VALUE`
- 互換用に `beat` / `step`、`game.zoom` / `hud.zoom`、`health.add` も使用可能

別のPulseファイルを起動するには、同じModの `logic/` 配下を指定します。

```text
onSongStart -> run logic/extra.pulse
```

起動できるのは `logic/` 配下の `.pulse` ファイルだけです。OSの `.sh`、`.py`、`.hx` などを実行する機能ではありません。

## 繰り返しと待機

```text
everyBeat -> setProperty camGame.zoom 1.05
everyStep -> setProperty camHUD.zoom 1.01
repeat 4 everyBeat -> emit.ZoomCamera 1.10
wait 32 steps -> setProperty camGame.zoom 1.00
```

`everyBeat` / `everyStep` は無期限に実行されます。`repeat` は指定回数だけ、`wait` は曲開始から指定した拍・ステップで一度だけ実行します。

`camGame.zoom` はゲームカメラ、`camHUD.zoom` はHUDカメラ、`health` はプレイヤーの体力を表します。beat／step番号は0始まりです。ズームは0.25〜2.5、体力は0〜2、体力の加算は-2〜2に制限されます。行頭または命令末尾の `#` 以降はコメントです。

Pulseは任意のHaxe/HScript、ファイルアクセス、reflection、eval、ループを実行しません。無効な命令はログに出して無視します。そのため、複雑な処理や公式APIの全機能が必要な場合は、従来どおりPolymodのHScript scripted class / moduleを使ってください。

Pulseのカスタムスクリプト実行は現在の実装ではnative (`sys`) ビルド向けです。既存のPolymodによるアセット置換とHScript Modは引き続き利用できます。

複雑な処理、任意の文字列引数、`Song` / `Stage` / `BaseCharacter` / `NoteKind` / `SongEvent` のクラス拡張、独自の`handleEvent()`は、公式と同じ`.hxc` scripted class / moduleで実装してください。Pulseはそれらを安全な固定命令に限定した補助APIです。
