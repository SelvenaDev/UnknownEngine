# FunkPulse 公式API互換リファレンス

FunkPulseは、公式のPolymod HScriptを置き換えるものではありません。公式HScriptで使われるイベント名・プロパティ名を、任意コードなしの安全な1行命令として使えるようにした互換レイヤーです。

公式の高度なModは、引き続き `mods/<mod>/scripts/` の `.hxc` scripted class / module を使用してください。公式資料は [Funkin Modding Documentation](https://funkincrew.github.io/funkin-modding-docs/) です。

## 基本構文

```text
EVENT [BEAT_OR_STEP_INDEX] -> ACTION VALUE
```

`onBeatHit` と `onStepHit` には必ず0始まりの番号を指定します。それ以外のイベントは番号を省略します。

```text
onBeatHit 8 -> setProperty camGame.zoom 1.05
onStepHit 32 -> setProperty camHUD.zoom 1.02
onSongStart -> setProperty playbackRate 1.0
onNoteHit -> addHealth 0.05
onBeatHit 16 -> emit.ZoomCamera 1.10
onStepHit 32 -> emit.ScrollSpeed 1.50
```

## 別のPulseファイルを起動する

同じMod内の `logic/` 配下にある別の `.pulse` ファイルを、イベント発生時に読み込めます。

```text
onSongStart -> run logic/extra.pulse
onBeatHit 64 -> run logic/section2.pulse
```

対象ファイルは安全のため `logic/` 配下の `.pulse` に限定されます。`..`、絶対パス、`.py`・`.sh`・`.hx` などの外部ファイルは起動できません。読み込んだファイルは同じMod内で一度だけ読み込まれ、循環参照も無視されます。

行頭または命令末尾の `#` 以降はコメントです。1ファイルの上限は128KiB、命令数の上限は1024個です。

## 公式ScriptEventコールバック対応

Pulseは、現在のEnhanced Funkinが実際にScriptEventDispatcherで処理するイベントを次の名前で受け取ります。

- `onCreate` — scripted object / moduleの生成
- `onStateCreate` — stateの生成完了
- `onDestroy` —破棄
- `onAdd` — stateへの追加
- `onUpdate` — 毎フレーム更新
- `onPause` / `onResume` — 一時停止・再開
- `onBeatHit N` / `onStepHit N` — 曲の拍・ステップ。番号は0始まり
- `onNoteIncoming` — ノーツが表示対象になったとき
- `onNoteHit` / `onNoteMiss` / `onNoteHoldDrop` — ノーツ判定
- `onNoteGhostMiss` — 空打ちミス
- `onSongEvent` — チャートのSong Event
- `onSongStart` / `onSongEnd` / `onSongRetry` — 曲の開始・終了・リトライ
- `onCountdownStart` / `onCountdownStep` / `onCountdownEnd` — カウントダウン
- `onSongLoaded` — 譜面ロード完了
- `onGameOver` — ゲームオーバー
- `onStateChangeBegin` / `onStateChangeEnd` — state切り替え前後
- `onSubStateOpenBegin` / `onSubStateOpenEnd` — substate開始前後
- `onSubStateCloseBegin` / `onSubStateCloseEnd` — substate終了前後
- `onFocusGained` / `onFocusLost` — ウィンドウフォーカス変更
- `onCapsuleSelected` / `onDifficultySwitch` / `onSongSelected` — Freeplay操作
- `onFreeplayIntroDone` / `onFreeplayOutro` / `onFreeplayClose` — Freeplay画面イベント
- `onCharacterSelect` / `onCharacterDeselect` / `onCharacterConfirm` — キャラクター選択
- `onDialogueStart` / `onDialogueLine` / `onDialogueCompleteLine` / `onDialogueSkip` / `onDialogueEnd` — 会話イベント

`KEY_DOWN` と `KEY_UP` は基礎enumに予約されていますが、公式の `IScriptedClass` には対応コールバックがなく、公式ディスパッチャからも発行されません。そのためPulseでも見かけだけの対応は追加していません。

## アクション

### カメラ

```text
setProperty camGame.zoom VALUE
setProperty camHUD.zoom VALUE
cameraZoom VALUE
hudZoom VALUE
```

`camGame.zoom` と `cameraZoom` はゲームカメラ、`camHUD.zoom` と `hudZoom` はHUDカメラに適用されます。値は0.25〜2.5です。

### 体力

```text
addHealth VALUE
setHealth VALUE
setProperty health VALUE
setProperty PlayState.instance.health VALUE
```

`addHealth` は-2〜2、`setHealth` は0〜2に制限されます。実行時にも0〜2へクランプします。

### PlayStateの公開プロパティ

```text
setProperty currentCameraZoom VALUE
setProperty defaultHUDCameraZoom VALUE
setProperty playbackRate VALUE
setProperty instrumentalVolume VALUE
setProperty playerVocalsVolume VALUE
setProperty opponentVocalsVolume VALUE
setProperty cameraBopIntensity VALUE
setProperty hudCameraZoomIntensity VALUE
setProperty cameraZoomRate VALUE
setProperty cameraZoomRateOffset VALUE
```

値の制限は、再生速度が0より大きく4以下、音量が0〜1、カメラ関連の強度・レートが0〜100です。`currentCameraZoom` と `defaultHUDCameraZoom` は0〜2.5です。

### PlayStateの操作と標準Song Event

次の命令は、公式`PlayState`の操作または既存の標準`SongEvent`を安全な固定フィールドで呼び出します。

```text
onBeatHit 8 -> setScrollSpeed 1.25
onBeatHit 9 -> setPlayerScrollSpeed 1.50
onBeatHit 10 -> setOpponentScrollSpeed 0.90
onBeatHit 16 -> emit.ZoomCamera 1.10
onBeatHit 20 -> emit.ScrollSpeed 1.50
onBeatHit 24 -> emit.SetCameraBop 2.00
onBeatHit 28 -> emit.SetTargetBopSpeed 2
onBeatHit 32 -> emit.FocusCamera 0
```

対応する標準Eventは `ZoomCamera`（zoom）、`ScrollSpeed`（scroll）、`SetCameraBop`（intensity）、`SetTargetBopSpeed`（rate）、`FocusCamera`（char）です。`FocusCamera`の値は0=プレイヤー、1=相手、2=ガールフレンドです。任意のEvent IDや任意のDynamicオブジェクトを受け付ける仕様にはしていません。

## 公式Scripted Classとの役割分担

公式ドキュメントで定義されている次のScripted Classは、従来のPolymod/HScriptで完全に利用できます。

- `Song`
- `BaseCharacter` と各種Character subclass
- `Stage` / `StageProp` / `Bopper`
- `Level`
- `NoteKind`
- `SongEvent`
- `PlayableCharacter`
- `FreeplayStyle` / `NoteStyle` / `Album`
- `Conversation` / `DialogueBox` / `Speaker`
- `MusicBeatState` / `MusicBeatSubState`
- `FunkinSprite`、`FlxSprite`、各種Group、Runtime Shader
- `Module`

実装済みのScripted Classラッパーには、上記のクラスに加えて次も含まれます。

- `ScriptedFunkinSprite` / `ScriptedFunkinVideoSprite`
- `ScriptedFunkinGroup`、`ScriptedFlxBasic`、`ScriptedFlxObject`、`ScriptedFlxSprite`、`ScriptedFlxSpriteGroup`
- `ScriptedFlxTypedGroup`、`ScriptedFlxState`、`ScriptedFlxSubState`、`ScriptedFlxTransitionableState`、`ScriptedFlxStrip`
- `ScriptedFlxRuntimeShader`
- `ScriptedStrumline`
- `ScriptedBopper` / `ScriptedStageProp`
- `ScriptedBackingCard` とScripted Freeplay DJ各種
- `ScriptedStickerPack`

これらのクラスを新規作成したり、引数付きメソッドを呼んだり、ノーツやキャラクターのオブジェクトを変更したりする処理は、Pulseに無理に詰め込まず、公式と同じ `.hxc` クラスで書く方が互換性と保守性に優れます。

## 標準Song Event

チャート側の標準Song Eventは既存の公式APIをそのまま利用できます。現在のソースには次のイベントが登録されています。

- `FocusCamera`
- `PlayAnimation`
- `ScrollSpeed`
- `SetCameraBop`
- `SetHealthIcon`
- `SetTargetBopSpeed`
- `ZoomCamera`

新しいチャートイベントを作る場合は、公式と同じ `SongEvent` subclass を作成し、`handleEvent()`、`getTitle()`、`getEventSchema()` を実装してください。
