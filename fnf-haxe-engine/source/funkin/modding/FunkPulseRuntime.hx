package funkin.modding;

// Enhanced Funkin fork: a safe declarative bridge for official-style mod commands.

import funkin.modding.events.ScriptEvent;
import funkin.modding.events.ScriptEvent.SongTimeScriptEvent;
import funkin.modding.events.ScriptEventType;
import funkin.Conductor;
import funkin.data.event.SongEventRegistry;
import funkin.data.song.SongData.SongEventData;
import funkin.play.PlayState;

private typedef FunkPulseCommand =
{
  var trigger:String;
  var index:Int;
  var action:String;
  var value:Float;
  var source:String;
  var filePath:String;
  var packRoot:String;
}

/**
 * Loads the Enhanced Funkin Pulse format.
 *
 * Pulse is deliberately declarative. It does not evaluate Haxe/HScript, access
 * arbitrary files, use reflection, or expose loops. The command names mirror
 * the official ScriptEvent callback names and common PlayState properties so
 * simple mods can be written without a custom Haxe class.
 *
 * Examples:
 *   onBeatHit 0 -> setProperty camGame.zoom 1.05
 *   onStepHit 16 -> setProperty camHUD.zoom 1.03
 *   onNoteHit -> addHealth 0.05
 *   onSongStart -> setProperty playbackRate 1.1
 */
class FunkPulseRuntime
{
  public static final FORMAT:String = 'funk-pulse/v1';
  static final MAX_SCRIPT_BYTES:Int = 131072;
  static final MAX_COMMANDS:Int = 1024;
  static final MAX_INDEX:Int = 100000;
  static final COMMAND_PATTERN:EReg = new EReg(
    '^(beat|step|onCreate|onStateCreate|onDestroy|onAdd|onUpdate|onPause|onResume|onSongStart|onSongEnd|onGameOver|onNoteIncoming|onNoteHit|onNoteMiss|onNoteHoldDrop|onNoteGhostMiss|onStepHit|onBeatHit|onSongEvent|onCountdownStart|onCountdownStep|onCountdownEnd|onSongLoaded|onSongRetry|onStateChangeBegin|onStateChangeEnd|onSubStateOpenBegin|onSubStateOpenEnd|onSubStateCloseBegin|onSubStateCloseEnd|onFocusGained|onFocusLost|onCapsuleSelected|onDifficultySwitch|onSongSelected|onFreeplayIntroDone|onFreeplayOutro|onFreeplayClose|onCharacterSelect|onCharacterDeselect|onCharacterConfirm|onDialogueStart|onDialogueLine|onDialogueCompleteLine|onDialogueSkip|onDialogueEnd)(?:\\s+([0-9]+))?\\s*->\\s*(game\\.zoom|hud\\.zoom|health\\.add|setProperty\\s+(?:camGame\\.zoom|camHUD\\.zoom|PlayState\\.instance\\.camGame\\.zoom|PlayState\\.instance\\.camHUD\\.zoom|health|PlayState\\.instance\\.health|currentCameraZoom|defaultHUDCameraZoom|playbackRate|instrumentalVolume|playerVocalsVolume|opponentVocalsVolume|cameraBopIntensity|hudCameraZoomIntensity|cameraZoomRate|cameraZoomRateOffset)|addHealth|setHealth|cameraZoom|hudZoom|setCameraZoom|setHudZoom|setScrollSpeed|setPlayerScrollSpeed|setOpponentScrollSpeed|setCameraBop|emit\\.(?:ZoomCamera|ScrollSpeed|SetCameraBop|SetTargetBopSpeed|FocusCamera))\\s+(-?[0-9]+(?:\\.[0-9]+)?)$',
    ''
  );
  static final RUN_PATTERN:EReg = new EReg(
    '^(beat|step|onCreate|onStateCreate|onDestroy|onAdd|onUpdate|onPause|onResume|onSongStart|onSongEnd|onGameOver|onNoteIncoming|onNoteHit|onNoteMiss|onNoteHoldDrop|onNoteGhostMiss|onStepHit|onBeatHit|onSongEvent|onCountdownStart|onCountdownStep|onCountdownEnd|onSongLoaded|onSongRetry|onStateChangeBegin|onStateChangeEnd|onSubStateOpenBegin|onSubStateOpenEnd|onSubStateCloseBegin|onSubStateCloseEnd|onFocusGained|onFocusLost|onCapsuleSelected|onDifficultySwitch|onSongSelected|onFreeplayIntroDone|onFreeplayOutro|onFreeplayClose|onCharacterSelect|onCharacterDeselect|onCharacterConfirm|onDialogueStart|onDialogueLine|onDialogueCompleteLine|onDialogueSkip|onDialogueEnd)(?:\\s+([0-9]+))?\\s*->\\s*run\\s+([A-Za-z0-9_/-]+\\.pulse)$',
    ''
  );

  static var commands:Array<FunkPulseCommand> = [];
  static var loadedScripts:Map<String, Bool> = new Map();

  public static function reload(modDirs:Array<String>, modRoot:String):Void
  {
    commands = [];
    loadedScripts = new Map();

    #if sys
    if (!sys.FileSystem.exists(modRoot)) return;

    for (modDir in modDirs)
    {
      if (!isSafeSegment(modDir)) continue;
      var packRoot:String = '$modRoot/$modDir';
      var manifestPath:String = '$packRoot/pulse.json';
      if (!sys.FileSystem.exists(manifestPath)) continue;

      try
      {
        var manifest:Dynamic = haxe.Json.parse(sys.io.File.getContent(manifestPath));
        var format:Dynamic = Reflect.field(manifest, 'format');
        var id:Dynamic = Reflect.field(manifest, 'id');
        var entry:Dynamic = Reflect.field(manifest, 'entry');
        if (format != FORMAT || id != modDir || !Std.isOfType(entry, String))
        {
          trace('[FunkPulse] Ignoring invalid manifest: $manifestPath');
          continue;
        }

        var scriptEntry:String = cast entry;
        if (!isSafeEntry(scriptEntry))
        {
          trace('[FunkPulse] Ignoring unsafe script path in $manifestPath');
          continue;
        }
        loadScript(packRoot, scriptEntry, '$modDir/$scriptEntry');
      }
      catch (error:Dynamic)
      {
        trace('[FunkPulse] Failed to load $manifestPath: $error');
      }
    }
    trace('[FunkPulse] Loaded ${commands.length} command(s) from enabled mods.');
    #else
    trace('[FunkPulse] Pulse packs require a native target in this build.');
    #end
  }

  /** Execute instructions matching the current official ScriptEvent. */
  public static function dispatch(event:ScriptEvent):Void
  {
    if (event == null || !event.shouldPropagate || event.eventCanceled || commands.length == 0) return;

    var trigger:String = eventTrigger(event);
    if (trigger == '') return;

    var index:Int = -1;
    switch (event.type)
    {
      case ScriptEventType.SONG_BEAT_HIT:
        var beatEvent:SongTimeScriptEvent = cast event;
        index = beatEvent.beat;
      case ScriptEventType.SONG_STEP_HIT:
        var stepEvent:SongTimeScriptEvent = cast event;
        index = stepEvent.step;
      default:
    }

    var state:Null<PlayState> = PlayState.instance;
    if (state == null) return;

    // A runFile command may append commands while dispatching. Iterate over a snapshot
    // so the newly loaded file starts on the next matching event, not mid-dispatch.
    for (command in commands.copy())
    {
      if (command.trigger == trigger && (command.index < 0 || command.index == index)) execute(command, state);
    }
  }

  static function eventTrigger(event:ScriptEvent):String
  {
    return switch (event.type)
    {
      case ScriptEventType.CREATE: 'onCreate';
      case ScriptEventType.STATE_CREATE: 'onStateCreate';
      case ScriptEventType.DESTROY: 'onDestroy';
      case ScriptEventType.ADDED: 'onAdd';
      case ScriptEventType.UPDATE: 'onUpdate';
      case ScriptEventType.PAUSE: 'onPause';
      case ScriptEventType.RESUME: 'onResume';
      case ScriptEventType.SONG_BEAT_HIT: 'onBeatHit';
      case ScriptEventType.SONG_STEP_HIT: 'onStepHit';
      case ScriptEventType.NOTE_INCOMING: 'onNoteIncoming';
      case ScriptEventType.NOTE_HIT: 'onNoteHit';
      case ScriptEventType.NOTE_MISS: 'onNoteMiss';
      case ScriptEventType.NOTE_HOLD_DROP: 'onNoteHoldDrop';
      case ScriptEventType.NOTE_GHOST_MISS: 'onNoteGhostMiss';
      case ScriptEventType.SONG_EVENT: 'onSongEvent';
      case ScriptEventType.SONG_START: 'onSongStart';
      case ScriptEventType.SONG_END: 'onSongEnd';
      case ScriptEventType.COUNTDOWN_START: 'onCountdownStart';
      case ScriptEventType.COUNTDOWN_STEP: 'onCountdownStep';
      case ScriptEventType.COUNTDOWN_END: 'onCountdownEnd';
      case ScriptEventType.GAME_OVER: 'onGameOver';
      case ScriptEventType.SONG_RETRY: 'onSongRetry';
      case ScriptEventType.SONG_LOADED: 'onSongLoaded';
      case ScriptEventType.STATE_CHANGE_BEGIN: 'onStateChangeBegin';
      case ScriptEventType.STATE_CHANGE_END: 'onStateChangeEnd';
      case ScriptEventType.SUBSTATE_OPEN_BEGIN: 'onSubStateOpenBegin';
      case ScriptEventType.SUBSTATE_OPEN_END: 'onSubStateOpenEnd';
      case ScriptEventType.SUBSTATE_CLOSE_BEGIN: 'onSubStateCloseBegin';
      case ScriptEventType.SUBSTATE_CLOSE_END: 'onSubStateCloseEnd';
      case ScriptEventType.FOCUS_GAINED: 'onFocusGained';
      case ScriptEventType.FOCUS_LOST: 'onFocusLost';
      case ScriptEventType.CAPSULE_SELECTED: 'onCapsuleSelected';
      case ScriptEventType.DIFFICULTY_SWITCH: 'onDifficultySwitch';
      case ScriptEventType.SONG_SELECTED: 'onSongSelected';
      case ScriptEventType.FREEPLAY_INTRO: 'onFreeplayIntroDone';
      case ScriptEventType.FREEPLAY_OUTRO: 'onFreeplayOutro';
      case ScriptEventType.FREEPLAY_CLOSE: 'onFreeplayClose';
      case ScriptEventType.CHARACTER_SELECTED: 'onCharacterSelect';
      case ScriptEventType.CHARACTER_DESELECTED: 'onCharacterDeselect';
      case ScriptEventType.CHARACTER_CONFIRMED: 'onCharacterConfirm';
      case ScriptEventType.DIALOGUE_START: 'onDialogueStart';
      case ScriptEventType.DIALOGUE_LINE: 'onDialogueLine';
      case ScriptEventType.DIALOGUE_COMPLETE_LINE: 'onDialogueCompleteLine';
      case ScriptEventType.DIALOGUE_SKIP: 'onDialogueSkip';
      case ScriptEventType.DIALOGUE_END: 'onDialogueEnd';
      default: '';
    }
  }

  static function parseScript(source:String, sourceName:String, packRoot:String):Void
  {
    var lineNumber:Int = 0;
    var added:Int = 0;
    for (rawLine in source.split('\n'))
    {
      lineNumber++;
      var line:String = StringTools.trim(rawLine);
      var commentIndex:Int = line.indexOf('#');
      if (commentIndex >= 0) line = StringTools.trim(line.substr(0, commentIndex));
      if (line.length == 0) continue;

      if (RUN_PATTERN.match(line))
      {
        var rawTrigger:String = RUN_PATTERN.matched(1);
        var trigger:String = normalizeTrigger(rawTrigger);
        var rawIndex:Null<String> = RUN_PATTERN.matched(2);
        var parsedIndex:Null<Int> = rawIndex == null || rawIndex == '' ? -1 : Std.parseInt(rawIndex);
        var filePath:String = RUN_PATTERN.matched(3);
        var indexedTrigger:Bool = trigger == 'onBeatHit' || trigger == 'onStepHit';
        if (parsedIndex == null || parsedIndex < -1 || parsedIndex > MAX_INDEX || (indexedTrigger && parsedIndex < 0) || !isSafeEntry(filePath))
        {
          trace('[FunkPulse] $sourceName:$lineNumber: unsafe or invalid Pulse file; skipped.');
          continue;
        }
        if (commands.length >= MAX_COMMANDS)
        {
          trace('[FunkPulse] Command limit reached; remaining directives were ignored.');
          return;
        }
        commands.push({trigger: trigger, index: parsedIndex, action: 'runFile', value: 0, source: '$sourceName:$lineNumber', filePath: filePath, packRoot: packRoot});
        added++;
        continue;
      }

      if (!COMMAND_PATTERN.match(line))
      {
        trace('[FunkPulse] $sourceName:$lineNumber: invalid directive; skipped.');
        continue;
      }

      var rawTrigger:String = COMMAND_PATTERN.matched(1);
      var trigger:String = normalizeTrigger(rawTrigger);
      var rawIndex:Null<String> = COMMAND_PATTERN.matched(2);
      var parsedIndex:Null<Int> = rawIndex == null || rawIndex == '' ? -1 : Std.parseInt(rawIndex);
      var action:String = normalizeAction(COMMAND_PATTERN.matched(3));
      var value:Float = Std.parseFloat(COMMAND_PATTERN.matched(4));
      var indexedTrigger:Bool = trigger == 'onBeatHit' || trigger == 'onStepHit';

      if (parsedIndex == null || parsedIndex < -1 || parsedIndex > MAX_INDEX || (indexedTrigger && parsedIndex < 0) || Math.isNaN(value))
      {
        trace('[FunkPulse] $sourceName:$lineNumber: invalid event index or value; skipped.');
        continue;
      }

      var validValue:Bool = switch (action)
      {
        case 'game.zoom', 'hud.zoom': value >= 0.25 && value <= 2.5;
        case 'health.add': value >= -2.0 && value <= 2.0;
        case 'setHealth': value >= 0.0 && value <= 2.0;
        default: isSafePropertyValue(action, value);
      };
      if (!validValue)
      {
        trace('[FunkPulse] $sourceName:$lineNumber: value outside the action limit; skipped.');
        continue;
      }
      if (commands.length >= MAX_COMMANDS)
      {
        trace('[FunkPulse] Command limit reached; remaining directives were ignored.');
        return;
      }

      commands.push({trigger: trigger, index: parsedIndex, action: action, value: value, source: '$sourceName:$lineNumber', filePath: '', packRoot: packRoot});
      added++;
    }
    trace('[FunkPulse] $sourceName: loaded $added command(s).');
  }

  static function normalizeTrigger(trigger:String):String
  {
    return switch (trigger)
    {
      case 'beat', 'onBeatHit': 'onBeatHit';
      case 'step', 'onStepHit': 'onStepHit';
      default: trigger;
    }
  }

  static function normalizeAction(action:String):String
  {
    return switch (action)
    {
      case 'setProperty camGame.zoom', 'setProperty PlayState.instance.camGame.zoom': 'game.zoom';
      case 'setProperty camHUD.zoom', 'setProperty PlayState.instance.camHUD.zoom': 'hud.zoom';
      case 'setProperty PlayState.instance.health': 'health';
      case 'addHealth': 'health.add';
      case 'cameraZoom': 'game.zoom';
      case 'hudZoom': 'hud.zoom';
      case 'setCameraZoom': 'game.zoom';
      case 'setHudZoom': 'hud.zoom';
      case 'setScrollSpeed': 'scrollSpeed';
      case 'setPlayerScrollSpeed': 'playerScrollSpeed';
      case 'setOpponentScrollSpeed': 'opponentScrollSpeed';
      case 'setCameraBop': 'cameraBopIntensity';
      default:
        if (StringTools.startsWith(action, 'setProperty ')) action.substr('setProperty '.length) else action;
    }
  }

  static function isSafePropertyValue(action:String, value:Float):Bool
  {
    return switch (action)
    {
      case 'health': value >= 0.0 && value <= 2.0;
      case 'game.zoom', 'hud.zoom': value >= 0.25 && value <= 2.5;
      case 'playbackRate': value > 0.0 && value <= 4.0;
      case 'instrumentalVolume', 'playerVocalsVolume', 'opponentVocalsVolume': value >= 0.0 && value <= 1.0;
      case 'cameraBopIntensity', 'hudCameraZoomIntensity', 'cameraZoomRate', 'cameraZoomRateOffset': value >= 0.0 && value <= 100.0;
      case 'currentCameraZoom', 'defaultHUDCameraZoom': value >= 0.0 && value <= 2.5;
      case 'scrollSpeed', 'playerScrollSpeed', 'opponentScrollSpeed': value >= 0.0 && value <= 10.0;
      case 'emit.ZoomCamera': value >= 0.0 && value <= 2.5;
      case 'emit.ScrollSpeed': value >= 0.0 && value <= 10.0;
      case 'emit.SetCameraBop': value >= 0.0 && value <= 10.0;
      case 'emit.SetTargetBopSpeed': value >= 0.0 && value <= 64.0;
      case 'emit.FocusCamera': value >= 0.0 && value <= 2.0;
      default: false;
    }
  }

  static function execute(command:FunkPulseCommand, state:PlayState):Void
  {
    switch (command.action)
    {
      case 'runFile':
        loadScript(command.packRoot, command.filePath, '${command.source} -> ${command.filePath}');
      case 'game.zoom':
        state.currentCameraZoom = command.value;
        state.camGame.zoom = command.value;
      case 'hud.zoom':
        state.defaultHUDCameraZoom = command.value;
        state.camHUD.zoom = command.value;
      case 'health.add':
        state.health = Math.max(0.0, Math.min(2.0, state.health + command.value));
      case 'health':
        state.health = command.value;
      case 'currentCameraZoom':
        state.currentCameraZoom = command.value;
        state.camGame.zoom = command.value;
      case 'defaultHUDCameraZoom':
        state.defaultHUDCameraZoom = command.value;
        state.camHUD.zoom = command.value;
      case 'playbackRate': state.playbackRate = command.value;
      case 'instrumentalVolume': state.instrumentalVolume = command.value;
      case 'playerVocalsVolume': state.playerVocalsVolume = command.value;
      case 'opponentVocalsVolume': state.opponentVocalsVolume = command.value;
      case 'cameraBopIntensity': state.cameraBopIntensity = command.value;
      case 'hudCameraZoomIntensity': state.hudCameraZoomIntensity = command.value;
      case 'cameraZoomRate': state.cameraZoomRate = command.value;
      case 'cameraZoomRateOffset': state.cameraZoomRateOffset = command.value;
      case 'scrollSpeed': state.tweenScrollSpeed(command.value, 0, null, ['playerStrumline', 'opponentStrumline']);
      case 'playerScrollSpeed': state.tweenScrollSpeed(command.value, 0, null, ['playerStrumline']);
      case 'opponentScrollSpeed': state.tweenScrollSpeed(command.value, 0, null, ['opponentStrumline']);
      case 'emit.ZoomCamera': emitSongEvent('ZoomCamera', {zoom: command.value}, command.source);
      case 'emit.ScrollSpeed': emitSongEvent('ScrollSpeed', {scroll: command.value}, command.source);
      case 'emit.SetCameraBop': emitSongEvent('SetCameraBop', {intensity: command.value}, command.source);
      case 'emit.SetTargetBopSpeed': emitSongEvent('SetTargetBopSpeed', {rate: Std.int(command.value)}, command.source);
      case 'emit.FocusCamera': emitSongEvent('FocusCamera', {char: Std.int(command.value)}, command.source);
      case 'setHealth': state.health = command.value;
      default: trace('[FunkPulse] Unsupported action at ${command.source}.');
    }
  }

  static function emitSongEvent(kind:String, value:Dynamic, source:String):Void
  {
    if (PlayState.instance == null || Conductor.instance == null) return;
    var data:SongEventData = new SongEventData(Conductor.instance.songPosition, kind, value);
    SongEventRegistry.handleEvent(data);
    trace('[FunkPulse] Emitted $kind from $source.');
  }

  static function isSafeSegment(value:String):Bool
  {
    return value.length > 0 && value != '.' && value != '..' && ~/^[A-Za-z0-9_-]+$/.match(value);
  }

  static function isSafeEntry(value:String):Bool
  {
    return StringTools.startsWith(value, 'logic/') && StringTools.endsWith(value, '.pulse') && value.indexOf('..') == -1
      && value.indexOf('\\') == -1 && !StringTools.startsWith(value, '/');
  }

  static function loadScript(packRoot:String, entry:String, sourceName:String):Void
  {
    #if !sys
    trace('[FunkPulse] Pulse file launch requires a native target: $sourceName');
    return;
    #else
    if (!isSafeEntry(entry))
    {
      trace('[FunkPulse] Unsafe Pulse file path ignored: $sourceName');
      return;
    }
    var scriptPath:String = '$packRoot/$entry';
    var scriptKey:String = '$packRoot/$entry';
    if (loadedScripts.exists(scriptKey)) return;
    loadedScripts.set(scriptKey, true);
    if (!sys.FileSystem.exists(scriptPath) || sys.FileSystem.isDirectory(scriptPath))
    {
      trace('[FunkPulse] Script not found: $scriptPath');
      return;
    }
    var source:String = sys.io.File.getContent(scriptPath);
    if (source.length > MAX_SCRIPT_BYTES)
    {
      trace('[FunkPulse] Script is too large and was ignored: $scriptPath');
      return;
    }
    parseScript(source, sourceName, packRoot);
    #end
  }
}
