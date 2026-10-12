# Enhanced Funkin — 改変内容

この作業コピーは、[FunkinCrew/Funkin](https://github.com/FunkinCrew/Funkin) の `b2215482c`（README／変更履歴上の0.8.7）を土台にしたHaxe改変版です。既存のプレイ処理とPolymodを維持しながら、視覚オフセットと、独自Modパック形式・スクリプト言語を追加しています。配布ZIPはソースコードとドキュメントのみで、Git履歴、依存ライブラリ、公式アート・音声アセットは含みません。

## 改良1 — Audio/Visual Offset

本家のセーブデータに存在していた `audioVisualOffset` をOffset画面につなぎ、±500msで保存・調整可能にしました。正方向は譜面ノーツを判定ライン側へ進め、負方向は遅らせます。音楽再生、判定時刻、スコアには影響しません。Calibrationの基準矢印では補正を無効にして測定バイアスを防ぎ、Testでは補正後の表示を確認できます。「Reset Offsets」で従来の全体オフセットと一緒に0へ戻せます。

## 改良2 — FunkPulse Mod形式

従来のPolymodアセット置換とHScript Modは残し、新しい「FunkPulse」形式を追加しました。ゲームの `mods/` に入れた各Modのルートに `pulse.json`、`logic/` 以下に `.pulse` スクリプトを置きます。Mod Menuから有効にしたパックだけ読み込まれます。`_polymod_meta.json` は既存Mod Menuとの互換メタデータです。

```text
mods/my-pack/
├── _polymod_meta.json  # Mod Menu互換用
├── pulse.json          # FunkPulse manifest
└── logic/
    └── main.pulse      # 宣言型スクリプト
```

`pulse.json` の最小例:

```json
{
  "format": "funk-pulse/v1",
  "id": "my-pack",
  "name": "My Pack",
  "version": "1.0.0",
  "entry": "logic/main.pulse"
}
```

### 公式API互換エイリアス

公式ドキュメントのHScriptは scripted class / module のイベントコールバックを中心に構成されています。この作業版のPulseは安全な限定DSLのまま、よく使うイベント名とプロパティ名を同じ考え方で書けるようにしました。

```text
onBeatHit 0 -> setProperty camGame.zoom 1.05
onStepHit 16 -> setProperty camHUD.zoom 1.03
onBeatHit 8 -> addHealth -0.05
onBeatHit 24 -> setHealth 1.00
```

`onBeatHit` は `SONG_BEAT_HIT`、`onStepHit` は `SONG_STEP_HIT` に対応します。`camGame.zoom`、`camHUD.zoom`、`health` は、それぞれゲームカメラ、HUDカメラ、`PlayState` の体力に対応します。従来の `beat` / `step`、`game.zoom` / `hud.zoom`、`health.add` も後方互換のため残しています。公式HScriptの任意コードを実行するものではないため、複雑な処理は従来のPolymod HScriptを利用してください。

Pulseは任意コードを評価しないイベント指向の小さなDSLです。ズーム値は0.25〜2.5、体力は0〜2、体力変化量は-2〜2です。行頭または命令末尾の `#` はコメント、無効な命令はログを出して無視します。スクリプトサイズと命令数にも上限を設け、ファイルアクセス・reflection・eval・ループ・任意Haxe/HScript実行は提供しません。**現実装のFunkPulse実行はnative (`sys`) ビルド向け**です。HTML5ビルドでは既存のPolymod/HScriptが引き続き利用できます。

動作例は `example_mods/pulseStarter/` にあります。このフォルダを `mods/` へコピーすると試せます。`pulse.json` の `id` とModフォルダ名を一致させてください。

## 変更ファイル

AV補正では `source/funkin/Preferences.hx`、`source/funkin/save/Save.hx`、`source/funkin/util/GRhythmUtil.hx`、`source/funkin/ui/options/OffsetMenu.hx` を変更しました。FunkPulseでは `source/funkin/modding/FunkPulseRuntime.hx` を追加し、`source/funkin/modding/PolymodHandler.hx` と `source/funkin/modding/module/ModuleHandler.hx` を更新しました。サンプルModは `example_mods/pulseStarter/` にあります。

## ビルドと確認

公式ソースのビルド手順に従って基準コミットを取得し、同梱の `ENHANCED_FUNKIN.patch` を適用してください。

```sh
git clone https://github.com/FunkinCrew/Funkin.git
cd Funkin
git checkout b2215482c
# ENHANCED_FUNKIN.patch をこのディレクトリへコピー
git apply ENHANCED_FUNKIN.patch
# 今回の公式API互換拡張を追加する場合
git apply ENHANCED_FUNKIN_API_COMPAT.patch
git submodule update --init --recursive
hmm install
haxelib run lime test html5
```

この作業環境では変更したHaxeモジュールの型チェック、パッチの適用検査、ソースZIPの整合性検査に成功しました。ゲーム全体の実行ビルドは未確認です。`git submodule update` は別ライセンスのゲームコンテンツを取得するため、配布物には同梱していません。

## ライセンスと表示

FNFソースコードと既存の著作権表示は、同梱 `LICENSE.md` のApache License 2.0に従います。変更したHaxeファイルにはこのフォークでの改変表示を付けています。`Friday Night Funkin'` とロゴの商標は The Funkin' Crew Inc. に帰属し、この改変版は公式製品ではありません。アート、音楽、音声などはソースとは別ライセンスのため、この配布物に含めていません。

## 公式API互換の調査範囲

公式Modding DocsのScripted Class / Scripted Module章と、同梱ソースの`ScriptEventType`、`IScriptedClass`、`Module`、`SongEvent`、`PlayState`を照合しました。Pulseは公式ディスパッチャが実際に処理する全ScriptEvent（生成、更新、曲、ノーツ、カウントダウン、画面遷移、Freeplay、キャラクター選択、会話）を`onXxx`命令として受け付けます。`KEY_DOWN` / `KEY_UP`はenumに予約されているだけで公式コールバックが存在しないため、動かない見せかけの互換命令は追加していません。

対応する公開プロパティと標準Song Eventの一覧は [`docs/FUNKPULSE_API.md`](docs/FUNKPULSE_API.md) にまとめています。複雑な引数、オブジェクト操作、カスタムクラス作成が必要な場合は、公式と同じPolymod HScriptの`.hxc` scripted class / moduleを使用してください。

さらに、標準Song Eventのうち安全に固定フィールドへ変換できる `ZoomCamera`、`ScrollSpeed`、`SetCameraBop`、`SetTargetBopSpeed`、`FocusCamera` を `emit.*` 命令として追加しました。`setScrollSpeed`、`setPlayerScrollSpeed`、`setOpponentScrollSpeed` はPlayStateの実際のStrumlineへ適用します。任意のSong Event ID、任意のDynamicデータ、StagePropやCharacterの任意メソッド呼び出しは引き続き公式Scripted Class側で実装します。

公式資料: [ソースコードとライセンス](https://github.com/FunkinCrew/Funkin/blob/main/LICENSE.md) · [公式Modding Docs](https://funkincrew.github.io/funkin-modding-docs/) · [FunkPulse互換リファレンス](docs/FUNKPULSE_API.md) · [コンパイルガイド](https://github.com/FunkinCrew/Funkin/blob/main/docs/COMPILING.md)
