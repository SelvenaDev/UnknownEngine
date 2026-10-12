package funkin.modding;

// Enhanced Funkin fork: a safe declarative bridge for official-style mod commands.

import funkin.modding.events.ScriptEvent;
import funkin.modding.events.ScriptEvent.SongTimeScriptEvent;
import funkin.modding.events.ScriptEventType;
import funkin.Conductor;
import funkin.data.event.SongEventRegistry;
import funkin.data.song.SongData.SongEventData;
import funkin.play.PlayState;
import funkin.audio.FunkinSound;
import funkin.play.cutscene.VideoCutscene;
import funkin.graphics.FunkinSprite;
import funkin.play.notes.NoteSprite;
import flixel.FlxSprite;
import flixel.FlxG;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import funkin.Paths;
import openfl.utils.Assets;

private typedef FunkPulseCommand =
{
  var trigger:String;
  var index:Int;
  var action:String;
  var value:Float;
  var source:String;
  var filePath:String;
  var packRoot:String;
  var repeatRemaining:Int;
  var args:Array<String>;
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
  static final ACTION_PATTERN:String = '(game\\.zoom|hud\\.zoom|health\\.add|setProperty\\s+(?:camGame\\.zoom|camHUD\\.zoom|PlayState\\.instance\\.camGame\\.zoom|PlayState\\.instance\\.camHUD\\.zoom|health|PlayState\\.instance\\.health|currentCameraZoom|defaultHUDCameraZoom|playbackRate|instrumentalVolume|playerVocalsVolume|opponentVocalsVolume|cameraBopIntensity|hudCameraZoomIntensity|cameraZoomRate|cameraZoomRateOffset)|addHealth|setHealth|cameraZoom|hudZoom|setCameraZoom|setHudZoom|setScrollSpeed|setPlayerScrollSpeed|setOpponentScrollSpeed|setCameraBop|emit\\.(?:ZoomCamera|ScrollSpeed|SetCameraBop|SetTargetBopSpeed|FocusCamera))';
  static final ADVANCED_PATTERN:EReg = new EReg('^(beat|step|onCreate|onStateCreate|onDestroy|onAdd|onUpdate|onPause|onResume|onSongStart|onSongEnd|onGameOver|onNoteIncoming|onNoteHit|onNoteMiss|onNoteHoldDrop|onNoteGhostMiss|onStepHit|onBeatHit|onSongEvent|onCountdownStart|onCountdownStep|onCountdownEnd|onSongLoaded|onSongRetry|onStateChangeBegin|onStateChangeEnd|onSubStateOpenBegin|onSubStateOpenEnd|onSubStateCloseBegin|onSubStateCloseEnd|onFocusGained|onFocusLost|onCapsuleSelected|onDifficultySwitch|onSongSelected|onFreeplayIntroDone|onFreeplayOutro|onFreeplayClose|onCharacterSelect|onCharacterDeselect|onCharacterConfirm|onDialogueStart|onDialogueLine|onDialogueCompleteLine|onDialogueSkip|onDialogueEnd)(?:\\s+([0-9]+))?\\s*->\\s*(tween|showImage|showText|setNote|removeVisual|clearVisuals|playSound|pauseSound|stopSound|tweenSound|playVideo|pauseVideo|stopVideo)(?:\\s+(.+))?$', '');
  static final EVERY_PATTERN:EReg = new EReg('^(everyBeat|everyStep)\\s*->\\s*' + ACTION_PATTERN + '\\s+(-?[0-9]+(?:\\.[0-9]+)?)$', '');
  static final REPEAT_PATTERN:EReg = new EReg('^repeat\\s+([1-9][0-9]{0,3})\\s+(everyBeat|everyStep)\\s*->\\s*' + ACTION_PATTERN + '\\s+(-?[0-9]+(?:\\.[0-9]+)?)$', '');
  static final WAIT_PATTERN:EReg = new EReg('^wait\\s+([1-9][0-9]{0,3})\\s+(beats|steps)\\s*->\\s*' + ACTION_PATTERN + '\\s+(-?[0-9]+(?:\\.[0-9]+)?)$', '');

  static var commands:Array<FunkPulseCommand> = [];
  static var loadedScripts:Map<String, Bool> = new Map();
  static var visuals:Map<String, FlxSprite> = new Map();
  static var texts:Map<String, FlxText> = new Map();
  static var visualCount:Int = 0;
  static var sounds:Map<String, FunkinSound> = new Map();
  static var videoPlaying:Bool = false;
  static var mediaCount:Int = 0;

  public static function reload(modDirs:Array<String>, modRoot:String):Void
  {
    commands = [];
    loadedScripts = new Map();
    clearVisuals();
    clearMedia();

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

    if (trigger == 'onSongEnd' || trigger == 'onDestroy' || trigger == 'onSongRetry') { clearVisuals(); clearMedia(); }

    // A runFile command may append commands while dispatching. Iterate over a snapshot
    // so the newly loaded file starts on the next matching event, not mid-dispatch.
    for (command in commands.copy())
    {
      if (command.trigger == trigger && (command.index < 0 || command.index == index) && command.repeatRemaining != 0)
      {
        if (command.repeatRemaining > 0) command.repeatRemaining--;
        execute(command, state);
      }
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

      var repeatRemaining:Int = -1;
      var trigger:String = '';
      var parsedIndex:Int = -1;
      var action:String = '';
      var value:Float = 0;

      if (EVERY_PATTERN.match(line))
      {
        trigger = EVERY_PATTERN.matched(1) == 'everyBeat' ? 'onBeatHit' : 'onStepHit';
        action = normalizeAction(EVERY_PATTERN.matched(2));
        value = Std.parseFloat(EVERY_PATTERN.matched(3));
      }
      else if (REPEAT_PATTERN.match(line))
      {
        var parsedRepeat:Null<Int> = Std.parseInt(REPEAT_PATTERN.matched(1));
        repeatRemaining = parsedRepeat == null ? 0 : parsedRepeat;
        trigger = REPEAT_PATTERN.matched(2) == 'everyBeat' ? 'onBeatHit' : 'onStepHit';
        action = normalizeAction(REPEAT_PATTERN.matched(3));
        value = Std.parseFloat(REPEAT_PATTERN.matched(4));
      }
      else if (WAIT_PATTERN.match(line))
      {
        var parsedWait:Null<Int> = Std.parseInt(WAIT_PATTERN.matched(1));
        parsedIndex = parsedWait == null ? -1 : parsedWait;
        trigger = WAIT_PATTERN.matched(2) == 'beats' ? 'onBeatHit' : 'onStepHit';
        repeatRemaining = 1;
        action = normalizeAction(WAIT_PATTERN.matched(3));
        value = Std.parseFloat(WAIT_PATTERN.matched(4));
      }

      if (trigger != '')
      {
        if (Math.isNaN(value) || !isSafePropertyValue(action, value))
        {
          trace('[FunkPulse] $sourceName:$lineNumber: invalid repeat/wait value; skipped.');
          continue;
        }
        if (commands.length >= MAX_COMMANDS)
        {
          trace('[FunkPulse] Command limit reached; remaining directives were ignored.');
          return;
        }
        commands.push({trigger: trigger, index: parsedIndex, action: action, value: value, source: '$sourceName:$lineNumber', filePath: '', packRoot: packRoot, repeatRemaining: repeatRemaining, args: []});
        added++;
        continue;
      }

      if (ADVANCED_PATTERN.match(line))
      {
        var advancedTrigger:String = normalizeTrigger(ADVANCED_PATTERN.matched(1));
        var advancedRawIndex:Null<String> = ADVANCED_PATTERN.matched(2);
        var advancedIndex:Null<Int> = advancedRawIndex == null || advancedRawIndex == '' ? -1 : Std.parseInt(advancedRawIndex);
        var advancedAction:String = ADVANCED_PATTERN.matched(3);
        var advancedRawArgs:Null<String> = ADVANCED_PATTERN.matched(4);
        var advancedArgs:Array<String> = parseAdvancedArgs(advancedAction, advancedRawArgs == null ? '' : advancedRawArgs);
        if (!isValidAdvanced(advancedAction, advancedArgs) || advancedIndex == null || advancedIndex < -1 || advancedIndex > MAX_INDEX
          || ((advancedTrigger == 'onBeatHit' || advancedTrigger == 'onStepHit') && advancedIndex < 0))
        {
          trace('[FunkPulse] $sourceName:$lineNumber: unsafe advanced directive; skipped.');
          continue;
        }
        if (commands.length >= MAX_COMMANDS) return;
        commands.push({trigger: advancedTrigger, index: advancedIndex, action: advancedAction, value: 0, args: advancedArgs,
          source: '$sourceName:$lineNumber', filePath: '', packRoot: packRoot, repeatRemaining: -1});
        added++;
        continue;
      }

      if (RUN_PATTERN.match(line))
      {
        var runRawTrigger:String = RUN_PATTERN.matched(1);
        trigger = normalizeTrigger(runRawTrigger);
        var runRawIndex:Null<String> = RUN_PATTERN.matched(2);
        var runParsedIndex:Null<Int> = runRawIndex == null || runRawIndex == '' ? -1 : Std.parseInt(runRawIndex);
        parsedIndex = runParsedIndex == null ? -1 : runParsedIndex;
        var filePath:String = RUN_PATTERN.matched(3);
        var runIndexedTrigger:Bool = trigger == 'onBeatHit' || trigger == 'onStepHit';
        if (runParsedIndex == null || runParsedIndex < -1 || runParsedIndex > MAX_INDEX || (runIndexedTrigger && runParsedIndex < 0) || !isSafeEntry(filePath))
        {
          trace('[FunkPulse] $sourceName:$lineNumber: unsafe or invalid Pulse file; skipped.');
          continue;
        }
        if (commands.length >= MAX_COMMANDS)
        {
          trace('[FunkPulse] Command limit reached; remaining directives were ignored.');
          return;
        }
        commands.push({trigger: trigger, index: parsedIndex, action: 'runFile', value: 0, source: '$sourceName:$lineNumber', filePath: filePath, packRoot: packRoot, repeatRemaining: -1, args: []});
        added++;
        continue;
      }

      if (!COMMAND_PATTERN.match(line))
      {
        trace('[FunkPulse] $sourceName:$lineNumber: invalid directive; skipped.');
        continue;
      }

      var rawTrigger:String = COMMAND_PATTERN.matched(1);
      trigger = normalizeTrigger(rawTrigger);
      var rawIndex:Null<String> = COMMAND_PATTERN.matched(2);
      var parsedIndex:Null<Int> = rawIndex == null || rawIndex == '' ? -1 : Std.parseInt(rawIndex);
      action = normalizeAction(COMMAND_PATTERN.matched(3));
      value = Std.parseFloat(COMMAND_PATTERN.matched(4));
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

      commands.push({trigger: trigger, index: parsedIndex, action: action, value: value, source: '$sourceName:$lineNumber', filePath: '', packRoot: packRoot, repeatRemaining: -1, args: []});
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
      case 'tween', 'showImage', 'showText', 'setNote', 'removeVisual', 'clearVisuals', 'playSound', 'pauseSound', 'stopSound', 'tweenSound', 'playVideo', 'pauseVideo', 'stopVideo': executeAdvanced(command, state);
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

  static function parseAdvancedArgs(action:String, raw:String):Array<String>
  {
    if (action == 'showText')
    {
      var match:EReg = new EReg('^([^ ]+)\\s+(-?[0-9]+(?:\\.[0-9]+)?)\\s+(-?[0-9]+(?:\\.[0-9]+)?)\\s+([1-9][0-9]{0,2})\\s+"([^"]{0,256})"(?:\\s+(hud|game))?$', '');
      if (match.match(raw)) return [match.matched(1), match.matched(2), match.matched(3), match.matched(4), match.matched(5), match.matched(6) ?? 'hud'];
      return [];
    }
    return raw.split(' ').filter(function(part) return part.length > 0);
  }

  static function isValidAdvanced(action:String, args:Array<String>):Bool
  {
    if (action == 'clearVisuals') return args.length == 0;
    if (action == 'playVideo') return args.length == 1 && isSafeAsset(args[0]);
    if (action == 'pauseVideo' || action == 'stopVideo') return args.length == 0;
    if (action == 'playSound') return args.length >= 3 && args.length <= 4 && isSafeId(args[0]) && isSafeAsset(args[1])
      && isSafeFloat(args[2], 0, 1) && (args.length == 3 || args[3] == 'loop' || args[3] == 'once');
    if (action == 'pauseSound' || action == 'stopSound') return args.length == 1 && isSafeId(args[0]);
    if (action == 'tweenSound') return args.length == 4 && isSafeId(args[0]) && args[1] == 'volume'
      && isSafeFloat(args[2], 0, 1) && isSafeFloat(args[3], 0.01, 10);
    if (action == 'removeVisual') return args.length == 1 && isSafeId(args[0]);
    if (action == 'showImage')
    {
      if (args.length < 4 || args.length > 5 || !isSafeId(args[0]) || !isSafeAsset(args[1])) return false;
      return isSafeFloat(args[2], -4096, 4096) && isSafeFloat(args[3], -4096, 4096) && (args.length == 4 || args[4] == 'hud' || args[4] == 'game');
    }
    if (action == 'showText')
      return args.length == 6 && isSafeId(args[0]) && isSafeFloat(args[1], -4096, 4096) && isSafeFloat(args[2], -4096, 4096)
        && isSafeFloat(args[3], 1, 256) && (args[5] == 'hud' || args[5] == 'game');
    if (action == 'setNote') return args.length == 4 && isSafeSide(args[0]) && isSafeInt(args[1], 0, 3)
      && isSafeNoteProperty(args[2]) && isSafeFloat(args[3], -4096, 4096);
    if (action == 'tween') return args.length >= 4 && args.length <= 5 && isSafeTarget(args[0]) && isSafeTweenProperty(args[1])
      && isSafeFloat(args[2], -4096, 4096) && isSafeFloat(args[3], 0.01, 10) && (args.length == 4 || isSafeEase(args[4]));
    return false;
  }

  static function isSafeId(value:String):Bool return value.length > 0 && value.length <= 32 && ~/^[A-Za-z0-9_-]+$/.match(value);
  static function isSafeAsset(value:String):Bool return value.length > 0 && value.length <= 128 && value.indexOf('..') < 0 && value.indexOf('\\') < 0 && !StringTools.startsWith(value, '/') && ~/^[A-Za-z0-9_/-]+$/.match(value);
  static function isSafeSide(value:String):Bool return value == 'player' || value == 'opponent';
  static function isSafeFloat(value:String, min:Float, max:Float):Bool { var n:Float = Std.parseFloat(value); return !Math.isNaN(n) && n >= min && n <= max; }
  static function isSafeInt(value:String, min:Int, max:Int):Bool { var n:Null<Int> = Std.parseInt(value); return n != null && n >= min && n <= max && value == Std.string(n); }
  static function isSafeNoteProperty(value:String):Bool return value == 'x' || value == 'yOffset' || value == 'alpha' || value == 'angle' || value == 'scale';
  static function isSafeTweenProperty(value:String):Bool return value == 'x' || value == 'y' || value == 'alpha' || value == 'angle' || value == 'scale' || value == 'scaleX' || value == 'scaleY';
  static function isSafeEase(value:String):Bool return value == 'linear' || value == 'quadIn' || value == 'quadOut' || value == 'quadInOut' || value == 'sineIn' || value == 'sineOut' || value == 'cubeIn' || value == 'cubeOut';
  static function isSafeTarget(value:String):Bool return (StringTools.startsWith(value, 'image:') || StringTools.startsWith(value, 'text:') || StringTools.startsWith(value, 'note:')) && isSafeId(value.substr(value.indexOf(':') + 1).split(':')[0]);

  static function executeAdvanced(command:FunkPulseCommand, state:PlayState):Void
  {
    var a:Array<String> = command.args;
    switch (command.action)
    {
      case 'clearVisuals': clearVisuals();
      case 'playSound': playSound(a);
      case 'pauseSound': pauseSound(a[0]);
      case 'stopSound': stopSound(a[0]);
      case 'tweenSound':
        var sound:Null<FunkinSound> = sounds.get(a[0]);
        if (sound != null) FlxTween.tween(sound, {volume: Std.parseFloat(a[2])}, Std.parseFloat(a[3]));
      case 'playVideo':
        if (!videoPlaying) { VideoCutscene.play(Paths.videos(a[0])); videoPlaying = true; mediaCount++; }
      case 'pauseVideo':
        if (videoPlaying) VideoCutscene.pauseVideo();
      case 'stopVideo':
        if (videoPlaying) { VideoCutscene.finishVideo(); videoPlaying = false; if (mediaCount > 0) mediaCount--; }
      case 'removeVisual': removeVisual(a[0], state);
      case 'showImage':
        if (visualCount >= 64 || !Assets.exists(Paths.image(a[1]))) return;
        removeVisual(a[0], state);
        var image:FunkinSprite = FunkinSprite.create(Std.parseFloat(a[2]), Std.parseFloat(a[3]), a[1]);
        image.cameras = [a.length == 5 && a[4] == 'game' ? state.camGame : state.camHUD];
        state.add(image); visuals.set(a[0], image); visualCount++;
      case 'showText':
        if (visualCount >= 64) return;
        removeVisual(a[0], state);
        var text:FlxText = new FlxText(Std.parseFloat(a[1]), Std.parseFloat(a[2]), 0, a[4], Std.parseInt(a[3]));
        text.cameras = [a[5] == 'game' ? state.camGame : state.camHUD];
        state.add(text); texts.set(a[0], text); visualCount++;
      case 'setNote':
        var note:Null<NoteSprite> = findNote(state, a[0], Std.parseInt(a[1]));
        if (note != null) setTargetProperty(note, a[2], Std.parseFloat(a[3]));
      case 'tween':
        var target:Dynamic = findTarget(state, a[0]);
        if (target != null) tweenTarget(target, a[1], Std.parseFloat(a[2]), Std.parseFloat(a[3]), a.length == 5 ? a[4] : 'linear');
    }
  }

  static function findNote(state:PlayState, side:String, index:Int):Null<NoteSprite>
  {
    var group = side == 'player' ? state.playerStrumline.notes : state.opponentStrumline.notes;
    return index >= 0 && index < group.members.length ? group.members[index] : null;
  }

  static function findTarget(state:PlayState, target:String):Dynamic
  {
    var parts:Array<String> = target.split(':');
    if (parts[0] == 'image') return visuals.get(parts[1]);
    if (parts[0] == 'text') return texts.get(parts[1]);
    if (parts[0] == 'note' && parts.length == 3 && isSafeSide(parts[1])) return findNote(state, parts[1], Std.parseInt(parts[2]));
    return null;
  }

  static function setTargetProperty(target:Dynamic, property:String, value:Float):Void
  {
    switch (property) { case 'x': target.x = value; case 'y': target.y = value; case 'yOffset': target.yOffset = value; case 'alpha': target.alpha = value; case 'angle': target.angle = value; case 'scale': target.scale.set(value, value); }
  }

  static function tweenTarget(target:Dynamic, property:String, value:Float, duration:Float, easeName:String):Void
  {
    var props:Dynamic = {}; switch (property) { case 'x': props.x = value; case 'y': props.y = value; case 'alpha': props.alpha = value; case 'angle': props.angle = value; case 'scale': props['scale.x'] = value; props['scale.y'] = value; case 'scaleX': props['scale.x'] = value; case 'scaleY': props['scale.y'] = value; }
    FlxTween.tween(target, props, duration, {ease: easeFor(easeName)});
  }

  static function easeFor(name:String):Float->Float return switch (name) { case 'quadIn': FlxEase.quadIn; case 'quadOut': FlxEase.quadOut; case 'quadInOut': FlxEase.quadInOut; case 'sineIn': FlxEase.sineIn; case 'sineOut': FlxEase.sineOut; case 'cubeIn': FlxEase.cubeIn; case 'cubeOut': FlxEase.cubeOut; default: FlxEase.linear; };

  static function playSound(args:Array<String>):Void
  {
    if (mediaCount >= 32) return;
    stopSound(args[0]);
    var looped:Bool = args.length == 4 && args[3] == 'loop';
    var loaded:Null<FunkinSound> = looped
      ? FunkinSound.load(Paths.sound(args[1]), Std.parseFloat(args[2]), true, false, true)
      : FunkinSound.playOnce(Paths.sound(args[1]), Std.parseFloat(args[2]));
    if (loaded != null) { sounds.set(args[0], loaded); mediaCount++; }
  }

  static function pauseSound(id:String):Void
  {
    var sound:Null<FunkinSound> = sounds.get(id);
    if (sound != null) sound.pause();
  }

  static function stopSound(id:String):Void
  {
    var sound:Null<FunkinSound> = sounds.get(id);
    if (sound != null) { sound.stop(); sound.destroy(); sounds.remove(id); if (mediaCount > 0) mediaCount--; }
  }

  static function removeVisual(id:String, state:PlayState):Void
  {
    var image:Null<FlxSprite> = visuals.get(id); if (image != null) { state.remove(image, true); image.destroy(); visuals.remove(id); visualCount--; }
    var text:Null<FlxText> = texts.get(id); if (text != null) { state.remove(text, true); text.destroy(); texts.remove(id); visualCount--; }
  }

  static function clearVisuals():Void
  {
    var state:Null<PlayState> = PlayState.instance; if (state != null) { for (image in visuals) { state.remove(image, true); image.destroy(); } for (text in texts) { state.remove(text, true); text.destroy(); } }
    visuals = new Map(); texts = new Map(); visualCount = 0;
  }

  static function clearMedia():Void
  {
    var soundIds:Array<String> = [for (id in sounds.keys()) id];
    for (id in soundIds) stopSound(id);
    if (videoPlaying) VideoCutscene.finishVideo();
    videoPlaying = false;
    mediaCount = 0;
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
