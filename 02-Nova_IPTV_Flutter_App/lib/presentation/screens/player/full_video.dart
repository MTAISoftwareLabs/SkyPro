part of '../screens.dart';

const int _kRapidDoubleTapMaxSeekSeconds = 360;
const Duration _okLongPressDuration = Duration(milliseconds: 1200);
const List<double> _kAspectRatios = [0, 16 / 9, 4 / 3, 21 / 9];

const Duration _kVodSeekBarHoldInterval = Duration(milliseconds: 200);
const Duration _kVodHoldSeekMinInterval = Duration(milliseconds: 140);

/// تأخير إنهاء السحب — ريموتات Android TV ترسل KeyUp متقطعاً أثناء الضغط.
const Duration _kVodSeekBarHoldKeyUpGrace = Duration(milliseconds: 220);
const Duration _kPlayerControlsIdleBeforeHide = Duration(seconds: 7);
const double _kIptvCatRowHeight = 36;
const double _kIptvChRowHeight = 37;
const Duration _kIptvNavDebounce = Duration(milliseconds: 40);

const Duration _kIptvCategoryCommitDelay = Duration(milliseconds: 110);
const Duration _kIptvCatReorderLongPress = Duration(milliseconds: 700);
const Duration _kLiveWatchQualifyDuration = Duration(seconds: 15);

/// Lecture seule — n'interrompt pas le live, assez lent pour les TV faibles.
const Duration _kLiveStreamInfoRefresh = Duration(seconds: 2);
const int _kIptvFocusEmptyRetries = 72;

/// Exo / VLC: نفس debounce للزاب السلس على الأجهزة الضعيفة.
const Duration _kLiveChannelSwitchDebounceExo = Duration(milliseconds: 160);
const Duration _kLiveChannelSwitchDebounceVlc = Duration(milliseconds: 160);

/// مهلة تحرير قفل التبديل — حتى لو القناة ميتة يُفرَّغ الـ pending.
const Duration _kLiveChannelSwitchTimeout = Duration(seconds: 3);

const int _kIptvPanelColCategories = 0;
const int _kIptvPanelColChannels = 1;
const int _kIptvPanelColPlayer = 2;

class FullVideoScreen extends StatefulWidget {
  const FullVideoScreen({
    super.key,
    required this.link,
    required this.title,
    this.isLive = false,
    this.channelMovie,
    this.channelLive,
    this.channelSerie,
    this.initialIsLiked = false,
    this.overridePlayer,
    this.initialLiveCategoryId,
    this.serieEpisodes,
    this.serieCurrentEpisodeId,
    this.serieUserAuth,
    this.initialPositionSeconds,
    this.autoResume = false,
    this.startInIptvBrowser = false,
  });
  final String link;
  final String title;
  final bool isLive;

  final ChannelMovie? channelMovie;
  final ChannelLive? channelLive;
  final ChannelSerie? channelSerie;
  final bool initialIsLiked;
  final AppVideoPlayer? overridePlayer;
  final String? initialLiveCategoryId;

  /// عند الفتح من شاشة Live: ابدأ مباشرة بوضع المتصفح (مشغّل مصغّر + قوائم).
  final bool startInIptvBrowser;

  /// Resume position in seconds when opening from continue-watching.
  final double? initialPositionSeconds;

  /// Skip resume dialog and seek+play from [initialPositionSeconds] immediately.
  final bool autoResume;

  /// Ã™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â© Ã˜Â­Ã™â€žÃ™â€šÃ˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã™Ë†Ã˜Â³Ã™â€¦ Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å  Ã™â€žÃ˜Â¹Ã˜Â±Ã˜Â¶ Ã˜Â§Ã™â€žÃ™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã™â€šÃ˜ÂªÃ˜Â±Ã˜Â­Ã˜Â©
  final List<Episode?>? serieEpisodes;

  /// id Ã˜Â§Ã™â€žÃ˜Â­Ã™â€žÃ™â€šÃ˜Â© Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â© Ã™â€žÃ˜ÂªÃ˜Â­Ã˜Â¯Ã™Å Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â­Ã™â€žÃ™â€šÃ˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â¯Ã˜Â¯Ã˜Â© Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â©
  final String? serieCurrentEpisodeId;

  /// Ã˜Â¨Ã™Å Ã˜Â§Ã™â€ Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã™â€žÃ˜Â¨Ã™â€ Ã˜Â§Ã˜Â¡ Ã˜Â±Ã˜Â§Ã˜Â¨Ã˜Â· Ã˜Â§Ã™â€žÃ˜Â­Ã™â€žÃ™â€šÃ˜Â© (serverUrl / user / pass)
  final UserModel? serieUserAuth;

  @override
  State<FullVideoScreen> createState() => _FullVideoScreenState();
}

class _FullVideoScreenState extends State<FullVideoScreen>
    with WidgetsBindingObserver {
  VlcPlayerController? _videoPlayerController;
  BetterPlayerController? _exoController;
  bool _exoValueListenerAttached = false;

  // Playback controller listeners can fire many times per second. The UI
  // does not need full-page processing at that rate; the player/watchdog has
  // its own timers for liveness. Coalesce passive listener work to ~12.5 Hz.
  DateTime _lastPlaybackListenerRun = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _playbackListenerMinInterval = Duration(
    milliseconds: 80,
  );

  bool _isPlaybackTransitionInProgress = false;

  /// Single source of truth for the URL currently being played (movie/episode/live).
  String get _activePlaybackUrl => _currentPlaybackUrl;
  String _currentPlaybackUrl = '';

  /// Increments on every source change; used to invalidate stale async work.
  int _activeSessionId = 0;

  /// True when user explicitly paused; listeners must not auto-resume.
  /// Prevents scheduling focus restore from multiple places at once.
  bool _focusRestoreScheduled = false;

  /// Session id for which initial resume seek was done; one-time per session.
  int? _initialResumeSeekDoneForSessionId;

  /// موقع الاستكمال بعد اختيار المستخدم (null = من البداية).
  double? _resumeSeekTargetSeconds;

  /// انتظار اختيار متابعة / بدأ من جديد قبل تشغيل الفيديو.
  bool _awaitingResumeChoice = false;
  double _pendingResumeSeconds = 0;

  /// غطّاء تحميل حتى تكتمل قفزة الاستكمال (يمنع ظهور 00:00).
  Timer? _resumeCoverReleaseTimer;

  bool isPlayed = true;
  bool progress = true;
  bool _isVlcBuffering = false;

  /// Debounce buffering overlay so flicker does not rebuild the whole player tree.
  Timer? _bufferingUiDebounce;
  bool showControllersVideo = true;
  bool _autoAdvanceRunning = false;
  int _autoAdvanceHandledSessionId = -1;
  DateTime? _lastDoubleTapSeekAt;
  int _rapidForwardSeekSeconds = 10;
  int _rapidBackwardSeekSeconds = 10;

  // ValueNotifiers Ã™â€žÃ™â€žÃ™Ë†Ã™â€šÃ˜Âª Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â±Ã™Å Ã˜Â· Ã¢â‚¬â€ Ã˜ÂªÃ˜ÂªÃ˜Â­Ã˜Â¯Ã˜Â« Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  setState Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ™â‚¬ parent
  final ValueNotifier<String> _positionVN = ValueNotifier('');
  final ValueNotifier<String> _durationVN = ValueNotifier('');
  final ValueNotifier<double> _sliderVN = ValueNotifier(0.0);
  final ValueNotifier<bool> _validPositionVN = ValueNotifier(false);
  final ValueNotifier<double> _maxDurationVN = ValueNotifier(1.0);

  /// Buffered end position in seconds (YouTube-style secondary track).
  final ValueNotifier<double> _bufferVN = ValueNotifier(0.0);
  // Ã™â€ Ã˜Â¨Ã™â€šÃ™Å  Ã™â€¡Ã˜Â°Ã™â€¡ Ã™â€žÃ™â€žÃ˜ÂªÃ™Ë†Ã˜Â§Ã™ÂÃ™â€š Ã™â€¦Ã˜Â¹ Ã˜Â¨Ã™â€šÃ™Å Ã˜Â© Ã˜Â§Ã™â€žÃ™Æ’Ã™Ë†Ã˜Â¯
  String get position => _positionVN.value;
  set position(String v) => _positionVN.value = v;
  String get duration => _durationVN.value;
  set duration(String v) => _durationVN.value = v;
  double get sliderValue => _sliderVN.value;
  set sliderValue(double v) => _sliderVN.value = v;
  bool get validPosition => _validPositionVN.value;
  set validPosition(bool v) => _validPositionVN.value = v;
  double get _maxDurationSeconds => _maxDurationVN.value;
  set _maxDurationSeconds(double v) => _maxDurationVN.value = v;
  double get _bufferSeconds => _bufferVN.value;
  set _bufferSeconds(double v) => _bufferVN.value = v;

  late AppVideoPlayer _currentPlayer;
  bool get _useExo => _currentPlayer == AppVideoPlayer.exo;

  final FocusNode _overlayFocusNode = FocusNode();

  Timer? _okLongPressTimer;
  bool _okLongPressTriggered = false;
  ChannelLive? _iptvOkLongPressChannel;
  int _iptvChannelFocusScheduleId = 0;
  int _iptvMiniPlayerFocusScheduleId = 0;

  /// Right/OK from categories: keep channel-focus retries alive across rebuilds.
  bool _iptvFocusMoveToChannelsPending = false;

  /// Ã˜Â¹Ã™â€ Ã˜Â¯Ã™â€¦Ã˜Â§ Ã˜ÂªÃ™Æ’Ã™Ë†Ã™â€  Ã˜Â¹Ã™â€ Ã˜Â§Ã˜ÂµÃ˜Â± Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™Æ’Ã™â€¦ Ã˜Â¸Ã˜Â§Ã™â€¡Ã˜Â±Ã˜Â©: Ã™â€žÃ˜Â§ Ã™â€ Ã™â€ Ã™ÂÃ™â€˜Ã˜Â° play/pause Ã˜Â¹Ã™â€žÃ™â€° KeyDown Ã˜Â¨Ã™â€ž Ã˜Â¹Ã™â€žÃ™â€° KeyUp Ã˜Â¥Ã™â€  Ã™â€žÃ™â€¦ Ã™Å Ã™Æ’Ã™â€  Ã˜Â¶Ã˜ÂºÃ˜Â·Ã˜Â§Ã™â€¹ Ã™â€¦Ã˜Â·Ã™Ë†Ã™â€˜Ã™â€žÃ˜Â§Ã™â€¹ (Ã™â€žÃ™â€žÃ™â€¦Ã™ÂÃ˜Â¶Ã™â€žÃ˜Â©).
  bool _okDeferPlayPauseUntilKeyUp = false;
  OverlayEntry? _favOverlayEntry;
  OverlayEntry? _playerToastEntry;
  DateTime? _lastRightKeyTime;
  DateTime? _lastLeftKeyTime;
  DateTime? _lastRemoteForwardSeekAt;
  DateTime? _lastRemoteBackwardSeekAt;
  bool _showSeekForwardHint = false;
  bool _showSeekBackwardHint = false;
  int _forwardSeekHintSeconds = 10;
  int _backwardSeekHintSeconds = 10;
  Timer? _seekHintTimer;

  Timer? _vlcResumeRetryTimer;

  bool _userRequestedLivePause = false;
  Timer? _vlcLiveWatchdogTimer;
  Timer? _vlcLiveReconnectTimer;

  /// Deadline: if THIS attempt never reaches real playback, cross to the
  /// other engine right away instead of retrying the same engine for a
  /// long time (see _kLiveNeverHealthyCrossFallback).
  Timer? _liveNeverHealthyTimer;
  DateTime? _vlcLiveStallSince;
  DateTime? _vlcLiveInitStallSince;
  DateTime? _vlcLiveBufferingSince;
  /// Exo: buffering بدون نمو للبافر (ستريم ميت وليس rebuffer عادي).
  DateTime? _exoBufferStarveSince;
  /// تأكيد متتالٍ قبل reconnect — يتجاهل ومضات قصيرة.
  int _exoStallConfirmTicks = 0;
  DateTime? _liveLastProgressAt;
  Duration? _liveLastPositionSnapshot;
  double? _liveLastBufferPercentSnapshot;
  bool _liveHadHealthyPlayback = false;
  DateTime? _livePlayingSince;
  DateTime? _liveKeepAliveArmedAt;
  int _vlcLiveReconnectAttempt = 0;
  bool _vlcLiveReconnectBusy = false;

  /// يمنع تداخل setMedia على نفس متحكّم VLC.
  bool _vlcLiveMediaSwapBusy = false;
  DateTime? _vlcLivePlayNudgeAt;

  /// بعد zapping: VLC يرجع scale=1 فيرسم الصورة بالحجم الأصلي أعلى اليسار.
  Timer? _vlcSurfaceFitTimer;
  int _vlcFitGeneration = 0;
  Size _vlcLastFitSize = Size.zero;
  Size _vlcLastLayoutSize = Size.zero;
  Size _exoLastFitSize = Size.zero;
  bool _vlcLayoutBump = false;
  bool _vlcVideoMutedForSwap = false;
  bool _vlcAwaitingNewLiveFrames = false;

  bool _showSeekLoading = false;
  Timer? _seekLoadingTimer;

  final FocusNode _settingsGearFocusNode = FocusNode();
  final FocusNode _streamInfoFocusNode = FocusNode();
  final ValueNotifier<Map<String, String>?> _liveStreamInfoBarVN =
      ValueNotifier<Map<String, String>?>(null);
  int _liveStreamInfoBarToken = 0;
  Timer? _liveStreamInfoRefreshTimer;
  bool _liveStreamInfoRefreshBusy = false;
  late final FocusNode _settingsButtonSkipNode;
  late final FocusNode _playButtonFocusNode;
  late final FocusNode _playButtonSkipNode;

  // Aspect Ratio — start at Fill so Exo covers the full screen like VLC.
  // Cycle: Fill → 16:9 → 4:3 → 21:9 → Fill...
  int _aspectRatioIndex = 0;
  double get _videoAspectRatio => _kAspectRatios[_aspectRatioIndex];
  final FocusNode _aspectRatioFocusNode = FocusNode();
  final FocusNode _liveFavoriteFocusNode = FocusNode();
  final FocusNode _liveBackFocusNode = FocusNode(debugLabel: 'live_back');
  final FocusNode _liveChannelsListFocusNode = FocusNode(
    debugLabel: 'live_channels_list',
  );

  /// شريط التقدّم (VOD أفلام/مسلسلات) للتحكّم بريمو التلفاز.
  final FocusNode _vodSeekBarFocusNode = FocusNode(debugLabel: 'vod_seek_bar');
  final FocusNode _vodBackFocusNode = FocusNode(debugLabel: 'vod_back');
  Timer? _vodSeekBarHoldTimer;
  DateTime? _lastVodHoldSeekEmittedAt;

  /// تأخير إنهاء السحب — ريموتات Android TV ترسل KeyUp متقطعاً أثناء الضغط.
  Timer? _vodSeekBarHoldKeyUpTimer;

  /// 1 = يمين (تقديم)، -1 = يسار (ترجيع)، 0 = لا سحب.
  int _vodSeekBarHoldDirection = 0;
  bool _vodSeekBarHoldActive = false;
  bool _vodScrubPausedPlayback = false;
  bool _wasPlayingBeforeVodScrub = false;
  Duration? _vodScrubUiPositionOverride;
  Duration? _vodScrubUiDurationOverride;
  bool _vodScrubPostReleaseUiLock = false;
  Timer? _vodScrubUiUnlockTimer;
  bool _vodScrubReleaseLoading = false;
  int _vlcSeekToken = 0;
  bool _vlcSeekShouldResume = false;
  Timer? _vlcSeekResumeTimer;

  bool _vodControlsLocked = false;
  Timer? _vodLockUnlockTimer;
  bool _vodLockHoldHintVisible = false;
  bool _vodLockSuppressNextTap = false;
  bool _vodLockHardwareHandlerAttached = false;
  bool _vodLockUnlockViaBackHold = false;
  bool _vodLockConsumeNextBack = false;
  DateTime? _vodLockBackUnlockedAt;
  Timer? _vodLockBackGraceTimer;
  Timer? _vodLockHintDismissTimer;
  DateTime? _vodLockHintShownAt;
  OverlayEntry? _vodLockToastEntry;
  final GlobalKey _exoPlayerGlobalKey = GlobalKey(debugLabel: 'exo_player');
  final GlobalKey _vlcPlayerGlobalKey = GlobalKey(debugLabel: 'vlc_player');
  final GlobalKey _iptvMiniPlayerSlotKey = GlobalKey(
    debugLabel: 'iptv_mini_player_slot',
  );
  final GlobalKey _playerVideoStackKey = GlobalKey(
    debugLabel: 'player_video_stack',
  );
  Rect? _iptvMiniPlayerSlotRect;

  /// آخر قياس سليم لخانة المصغّر — يُستعاد عند الرجوع من fullscreen لتفادي شاشة فارغة.
  Rect? _iptvMiniPlayerSlotRectCache;
  bool _iptvMiniSlotMeasureScheduled = false;
  final FocusNode _vodLockFocusNode = FocusNode(debugLabel: 'vod_lock');
  final FocusNode _vodAudioSubsFocusNode = FocusNode(
    debugLabel: 'vod_audio_subs',
  );
  final FocusNode _vodSpeedFocusNode = FocusNode(debugLabel: 'vod_speed');
  final FocusNode _vodPipFocusNode = FocusNode(debugLabel: 'vod_pip');
  final FocusNode _liveAudioFocusNode = FocusNode(debugLabel: 'live_audio');

  /// Live audio sheet: highlight/apply "Default" until user picks a language.
  bool _liveAudioUseDefault = true;

  /// YouTube-style VOD rates (Exo allows 0 < speed ≤ 2).
  double _playbackSpeed = 1.0;

  /// Keeps remote focus inside speed/audio sheets (idle hide must not steal it).
  bool _playerOptionSheetOpen = false;
  bool _liveAudioPickerBusy = false;
  bool _isInPipMode = false;
  bool _enteringPipMode = false;
  bool _wasPlayingBeforePip = false;
  Timer? _pipKeepAliveTimer;

  Timer? _exoStartTimeoutTimer;
  bool _exoVodColdRetryUsed = false;

  /// Live Exo: try HLS then progressive TS (same player — no VLC hop).
  List<String> _exoLiveUrlCandidates = const [];
  int _exoLiveUrlCandidateIndex = 0;
  bool _exoLiveCandidateRetryBusy = false;

  Timer? _playerControlsIdleTimer;

  final FocusNode _rootPlayerFocusNode = FocusNode();
  bool _isSwitchingLiveChannel = false;

  /// غطاء أسود فوق سطح VLC أثناء تبديل القناة / دخول ملء الشاشة
  /// (يمنع بقاء إطار القناة السابقة على texture بعد setMedia).
  bool _iptvSurfaceTransitionCover = false;
  Timer? _iptvSurfaceCoverClearTimer;

  /// بعد زاب لقناة ميتة: أخفِ PlatformView حتى يبدأ بث حي فعلي (يمنع آخر frame صغير أعلى اليسار).
  bool _liveBlankSurfaceUntilPlay = false;

  /// الرابط الذي فُتح الغطاء لأجله — لا ترفع الغطاء على isPlaying من القناة السابقة.
  String? _liveSurfaceCoverForUrl;

  /// VLC laid out fullscreen but off-screen until the new stream is ready.
  bool _vlcParkOffscreen = false;

  ChannelLive? _pendingLiveChannel;
  String? _pendingLiveLink;

  /// يزداد مع كل تبديل قناة — يلغي أي `_startPlayback` عالق على قناة ميتة.
  int _liveSwitchGeneration = 0;

  /// Debounce rapid live channel zaps (Media3: load only final selection).
  Timer? _liveChannelSwitchDebounce;
  int _epgLoadGeneration = 0;
  ChannelLive? _currentLiveChannel;

  // ---------------------------------------------------------------------------
  // TiviMate-style live IPTV side panel (categories + channels, video keeps playing)
  // ---------------------------------------------------------------------------
  bool _showLiveIptvOverlay = false;

  /// أول دخول لقسم Live: خلفية ثابتة أولاً ثم تركيب اللوحة بعد إطارين
  /// حتى لا يتجمّد/يتقطع الإطار أثناء الانتقال على الأجهزة الضعيفة.
  bool _iptvBrowserUiReady = true;
  Timer? _iptvBrowserUiReadyTimer;

  /// يمنع تكرار الخروج للرئيسية عند ضغط رجوع الريموت + PopScope معاً.
  bool _exitingIdleLive = false;
  final FocusNode _iptvOverlayFocusNode = FocusNode(
    debugLabel: 'iptv_overlay_shell',
  );
  final FocusNode _iptvMiniPlayerFocusNode = FocusNode(
    debugLabel: 'iptv_mini_player',
  );
  final ScrollController _iptvCategoryScrollController = ScrollController();
  final ScrollController _iptvChannelScrollController = ScrollController();
  Timer? _iptvOverlayIdleTimer;

  /// Debounced channel switch while browsing the IPTV list (focus moves).
  Timer? _channelSwitchDebounce;
  String? _iptvActiveCategoryId;
  String _iptvCategorySearch = '';
  final FocusNode _iptvCategorySearchNavFocus = FocusNode(
    debugLabel: 'iptv_category_search_nav',
  );
  final FocusNode _iptvCategorySearchEditFocus = FocusNode(
    debugLabel: 'iptv_category_search_edit',
  );
  final FocusNode _iptvCategoriesBackFocusNode = FocusNode(
    debugLabel: 'iptv_categories_back',
  );
  bool _iptvTvSearchKeyboardOpen = false;

  /// Sidebar category used when the current channel was last picked (favorites fix).
  String? _iptvPickCategoryId;
  List<FocusNode> _iptvCategoryFocusNodes = [];
  List<FocusNode> _iptvChannelFocusNodes = [];
  int _iptvLastCategoryFocusIndex = 0;
  int _iptvLastChannelFocusIndex = 0;
  String? _iptvChannelFocusBoundCategoryId;
  DateTime? _iptvLastNavKeyTime;
  VoidCallback? _iptvPrimaryFocusListener;
  Timer? _iptvRestoreFocusTimer;
  Timer? _iptvCategoryCommitTimer;
  String? _iptvPendingCategoryId;
  bool _iptvRequestCategoryFocusAfterNextCatSync = false;

  /// After opening overlay: focus playing row once channel list nodes are ready.
  bool _iptvFocusPlayingChannelAfterChannelSync = false;

  /// Last column the user navigated in (for primary-focus restore).
  bool _iptvOverlayFocusOnChannelsColumn = false;
  bool _iptvOverlayFocusOnMiniPlayer = false;
  int _iptvActivePanelColumn = _kIptvPanelColCategories;
  final Map<String, int> _iptvCategoryChannelCounts = {};
  final Map<String, String> _iptvCategoryThumbUrls = {};
  bool _iptvMetaPrefetchStarted = false;
  Timer? _iptvMetaSetStateTimer;
  Timer? _iptvMetaPrefetchDelayTimer;

  /// ترتيب فئات Live المحفوظ (بدون المفضلة). يبقى بعد إعادة فتح التطبيق.
  List<String> _iptvPersistedCatOrder = const [];
  bool _iptvCatOrderLoaded = false;

  /// وضع ترتيب التلفاز: الفئة حرة وتُحرَّك بالأسهم حتى OK.
  int? _iptvTvReorderIndex;
  List<String>? _iptvTvReorderWorkingIds;
  Timer? _iptvCatReorderLongPressTimer;
  bool _iptvCatReorderLongPressTriggered = false;
  bool _iptvIgnoreNextCatOkUp = false;

  /// يمنع إغلاق اللوحة فوراً بعد الرجوع من ملء الشاشة (KeyUp لـ OK ينتقل لعقدة القناة).
  bool _iptvIgnoreNextChannelOkUp = false;
  Timer? _iptvIgnoreChannelOkTimer;

  List<ChannelLive> _iptvRecentlyWatched = const [];
  bool _iptvRecentlyWatchedLoaded = false;
  Timer? _liveWatchQualifyTimer;
  DateTime? _liveWatchSegmentStart;
  Duration _liveWatchAccumulated = Duration.zero;
  ChannelLive? _liveWatchTrackedChannel;
  bool _liveWatchQualified = false;

  /// لا تُحتسب المشاهدة إلا بعد تقدّم حقيقي للصورة — القنوات الميتة لا تُضاف.
  bool _liveWatchSawRealProgress = false;

  // ---------------------------------------------------------------------------
  // Movie Suggestions Overlay
  // ---------------------------------------------------------------------------
  bool _showMovieSuggestionsOverlay = false;
  final GlobalKey<_MovieSuggestionsOverlayState> _movieOverlayKey =
      GlobalKey<_MovieSuggestionsOverlayState>();
  final FocusNode _movieOverlayFocusNode = FocusNode();
  ChannelMovie? _currentMovie;
  late String _currentPlaybackTitle;

  /// تقدّم VOD داخل جلسة المشغّل (فيلم/حلقة) لاستكماله عند الرجوع بعد التبديل.
  final Map<String, double> _sessionVodProgressByStreamId = {};

  // ---------------------------------------------------------------------------
  // Episode Suggestions Overlay (للمسلسلات)
  // ---------------------------------------------------------------------------
  bool _showEpisodeSuggestionsOverlay = false;
  final GlobalKey<_EpisodeSuggestionsOverlayState> _episodeOverlayKey =
      GlobalKey<_EpisodeSuggestionsOverlayState>();
  final FocusNode _episodeOverlayFocusNode = FocusNode();
  String? _currentEpisodeId;
  FocusNode? _vodRestoreToolbarFocusNode;

  // Live channel suggestions (same category)
  bool _showLiveChannelSuggestionsOverlay = false;
  final GlobalKey<_LiveChannelSuggestionsOverlayState> _liveChannelOverlayKey =
      GlobalKey<_LiveChannelSuggestionsOverlayState>();
  final FocusNode _liveChannelOverlayFocusNode = FocusNode();

  // تلميح "اضغط سهم الأسفل لفتح قائمة الأفلام"
  bool _showMovieDownHint = false;
  bool _showLiveDownHint = false;

  // ---------------------------------------------------------------------------
  // [FIX 2] Ã˜Â£Ã˜Â¶Ã™ÂÃ™â€ Ã˜Â§ _epgRefreshTimer Ã™â€žÃ™â€žÃ˜ÂªÃ˜Â­Ã˜Â¯Ã™Å Ã˜Â« Ã˜Â§Ã™â€žÃ˜Â¯Ã™Ë†Ã˜Â±Ã™Å  Ã™â€žÃ™â€žÃ™â‚¬ EPG Ã™Æ’Ã™â€ž Ã˜Â¯Ã™â€šÃ™Å Ã™â€šÃ˜ÂªÃ™Å Ã™â€
  // ---------------------------------------------------------------------------
  Timer? _epgRefreshTimer;
  late final Dio
  _epgDio; // Dio Ã˜Â¯Ã˜Â§Ã˜Â¦Ã™â€¦ Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨Ã˜Â§Ã˜Âª EPG
  Timer? _movieHintShowTimer;
  Timer? _movieHintHideTimer;
  Timer? _liveHintShowTimer;
  Timer? _liveHintHideTimer;
  Timer? _resumeSeekTimer1;
  Timer? _resumeSeekTimer2;

  /// Ã˜ÂªÃ˜Â£Ã˜Â®Ã™Å Ã˜Â± Ã™â€šÃ˜ÂµÃ™Å Ã˜Â± Ã™â€šÃ˜Â¨Ã™â€ž seek Ã˜Â§Ã˜Â³Ã˜ÂªÃ˜Â¦Ã™â€ Ã˜Â§Ã™Â Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜Â§Ã™â€¡Ã˜Â¯Ã˜Â© Ã˜Â­Ã˜ÂªÃ™â€° Ã™Å Ã™ÂÃ˜Â±Ã˜Â³Ã™Å½Ã™â€¦ Ã˜Â¥Ã˜Â·Ã˜Â§Ã˜Â± Ã™ÂÃ™Å Ã˜Â¯Ã™Å Ã™Ë† Ã˜Â£Ã™Ë†Ã™â€ž Ã™Ë†Ã™Å Ã™â€šÃ™â€žÃ™â€˜ Ã‚Â«Ã˜ÂµÃ™Ë†Ã˜Âª Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  Ã˜ÂµÃ™Ë†Ã˜Â±Ã˜Â©Ã‚Â».
  Timer? _warmupResumeSeekTimer;
  int? _resumeSeekWarmupScheduledSessionId;

  EpgProgram? _currentProgram;
  EpgProgram? _nextProgram;

  // Phone-only brightness / volume edge gestures (left / right vertical pills).
  /// First-open hint: both pills with controls, then never again until re-enter.
  bool _bvIntroPending = true;
  bool _bvOverlayVisible = false;
  bool _bvIsBrightness = true;
  double _bvBrightness = 0.5;
  double _bvVolume = 0.5;
  double _bvGestureStartValue = 0;
  double _bvDragAccumulated = 0;
  _BvGestureKind? _bvActiveKind;
  bool _bvGestureConsumed = false;

  /// Start X for vertical drags — suggestions ignore left/right B/V edge zones.
  double _swipeDragStartDx = 0;
  double _swipeDragAccumulatedDy = 0;
  double _swipeDragAbsDy = 0;

  /// Suppresses control-toggle tap right after a recognized suggestion swipe.
  bool _suggestionSwipeJustHandled = false;
  Timer? _suggestionSwipeTapGuardTimer;
  Timer? _bvHideTimer;

  bool get _isMovieStyle => widget.channelMovie != null;
  bool get _isSeriesStyle => widget.channelSerie != null;
  bool get _isLiveFullscreenPlayer => widget.isLive && !_showLiveIptvOverlay;

  // ---------------------------------------------------------------------------
  // Session and playback helpers
  /// Safe setState for use from library extensions (avoids protected-member warnings).
  void _fvSetState([VoidCallback? fn]) {
    if (!mounted) return;
    setState(fn ?? () {});
  }

  void _scheduleFullVideoRebuild([VoidCallback? update]) {
    _fvSetState(update);
  }

  @override
  void initState() {
    super.initState();
    AdsService.setFullscreenPlaybackActive(true);

    _epgDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    WidgetsBinding.instance.addObserver(this);

    // iOS: VLC دائماً (أفلام + بث).
    // Android أفلام/مسلسلات: Exo فقط على كل الأجهزة (تلفاز/هاتف/بوكس).
    // Android بث: يحترم الإعدادات / الجلسة.
    if (Platform.isIOS) {
      _currentPlayer = AppVideoPlayer.vlc;
    } else if (!widget.isLive) {
      _currentPlayer = AppVideoPlayer.exo;
    } else {
      _currentPlayer = widget.overridePlayer ?? preferredVideoPlayer;
    }

    final idleLiveBrowser =
        widget.isLive &&
        widget.startInIptvBrowser &&
        widget.channelLive == null;

    if (idleLiveBrowser) {
      _showLiveIptvOverlay = true;
      var catsReady = false;
      try {
        final st = context.read<LiveCatyBloc>().state;
        catsReady = st is LiveCatySuccess && st.categories.isNotEmpty;
      } catch (_) { /* ignore */ }
      _iptvBrowserUiReady = catsReady;
      final initialCat = widget.initialLiveCategoryId?.trim();
      if (initialCat != null && initialCat.isNotEmpty) {
        _iptvActiveCategoryId = initialCat;
      }
      _iptvRequestCategoryFocusAfterNextCatSync = true;
      _iptvOverlayFocusOnChannelsColumn = false;
    }

    if (!idleLiveBrowser) {
      _beginNewPlaybackSession(widget.link);
    } else {
      _currentPlaybackUrl = '';
      _isPlaybackTransitionInProgress = false;
    }

    _currentMovie = widget.channelMovie;
    _currentPlaybackTitle = widget.title;

    _currentEpisodeId = widget.serieCurrentEpisodeId;

    // Lock orientation while this player is open to prevent any flip when
    // changing aspect ratio or when overlays trigger rebuilds.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (!idleLiveBrowser) {
      PlaybackWakelockService.instance
          .acquire(title: widget.title, isLive: widget.isLive)
          .ignore();
    }

    final initialPos = widget.initialPositionSeconds;
    if (!widget.isLive &&
        !widget.autoResume &&
        shouldOfferResumePlayback(positionSeconds: initialPos)) {
      _awaitingResumeChoice = true;
      _pendingResumeSeconds = initialPos!;
      _resumeSeekTargetSeconds = null;
      isPlayed = false;
      showControllersVideo = true;
    } else if (initialPos != null && initialPos > 0) {
      _resumeSeekTargetSeconds = initialPos;
      _scheduleDeferredResumeSeekTimers(initialPos);
    }
    if (!idleLiveBrowser) {
      // دائماً نحمّل المشغّل؛ الحوار يظهر فوقه والفيديو يبقى متوقفاً حتى الاختيار.
      _initPlayerAfterFirstFrame();
    }
    _settingPage();

    if (widget.isLive &&
        (widget.channelLive != null || widget.startInIptvBrowser)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.channelLive != null) {
          _persistLastLiveChannel(
            channel: widget.channelLive,
            link: widget.link,
          );
          _loadLiveEpg();
        }
        if (widget.initialLiveCategoryId != null &&
            widget.initialLiveCategoryId!.trim().isNotEmpty) {
          _iptvActiveCategoryId = widget.initialLiveCategoryId!.trim();
        }
        final idleLiveBrowser =
            widget.startInIptvBrowser && widget.channelLive == null;
        if (idleLiveBrowser && !_iptvBrowserUiReady) {
          _scheduleIdleLiveBrowserReveal();
        } else {
          _prefetchLiveIptvPanelData(preferSilentCache: idleLiveBrowser);
          if (idleLiveBrowser) {
            _iptvSeedCategoryMetaFromCache();
          }
          if (widget.startInIptvBrowser) {
            if (_showLiveIptvOverlay) {
              _prepareLiveIptvOverlayAfterMount();
            } else {
              _openLiveIptvOverlay();
            }
          }
        }
      });

      // [FIX 2] تحديث EPG دورياً كل دقيقتين لمواكبة تغيير البرامج
      // لا نربطه بـ sessionId لأن EPG يجب أن يتحدث مع كل قناة جديدة
      _epgRefreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        if (mounted &&
            (_currentLiveChannel != null || widget.channelLive != null)) {
          _loadLiveEpg();
        }
      });
    }

    _settingsGearFocusNode.addListener(_onSettingsGearFocusChange);
    _streamInfoFocusNode.addListener(_onStreamInfoFocusChange);
    _aspectRatioFocusNode.addListener(_onAspectRatioFocusChange);
    _liveFavoriteFocusNode.addListener(_onLiveFavoriteFocusChange);
    _vodSeekBarFocusNode.addListener(_onVodSeekBarFocusChange);
    _settingsButtonSkipNode = FocusNode(skipTraversal: true);
    // Play/pause can take focus, but stays out of nextFocus() traversal
    // so seek → toolbar navigation is not stolen.
    _playButtonFocusNode = FocusNode(skipTraversal: true);
    _playButtonSkipNode = FocusNode(skipTraversal: true);

    // إخفاء الأزرار فقط بعد خمول فعلي — يُعاد ضبطه بـ [_touchPlayerControlsActivity].
    if (!_awaitingResumeChoice && !idleLiveBrowser) {
      _schedulePlayerControlsHideAfterIdle();
    }

    if (widget.isLive && !idleLiveBrowser) {
      _showLiveHintOnce();
    } else if (!widget.isLive) {
      _showMovieHintOnce();
    }
  }

  void _iptvRememberPickCategory() {
    final active = _iptvActiveCategoryId;
    if (active == null || active.isEmpty) return;
    _iptvPickCategoryId = active;
  }

  /// Passive listener: observation only. No autoplay or delayed play from here.
  void listener() {
    if (!mounted) return;

    // VLC/Exo value listeners may fire at a much higher rate than the UI can
    // use. Coalesce duplicate ticks to reduce Dart CPU and rebuild pressure.
    final now = DateTime.now();
    if (now.difference(_lastPlaybackListenerRun) <
        _playbackListenerMinInterval) {
      return;
    }
    _lastPlaybackListenerRun = now;

    try {
      if (_useExo) {
        _handleExoListenerTick();
      } else {
        _handleVlcListenerTick();
      }
    } catch (e) { /* ignore */ }
  }

  @override
  void deactivate() {
    // Clear before dispose — Get.to().then often runs while flag is still true
    // and would permanently skip interstitial after leaving the player.
    AdsService.setFullscreenPlaybackActive(false);
    // If we already halted for Home exit, controllers are null — no-op.
    // Otherwise force stop so nothing keeps decoding in the background.
    if (_exoController != null || _videoPlayerController != null) {
      unawaited(_haltAllPlaybackForLeave());
    }
    _hidePlayerInitToast();
    super.deactivate();
  }

  @override
  void dispose() {
    AdsService.setFullscreenPlaybackActive(false);
    try {
      _persistLastLiveChannel();
    } catch (_) { /* ignore */ }
    try {
      _epgDio.close(force: true);
    } catch (_) { /* ignore */ }
    try {
      WidgetsBinding.instance.removeObserver(this);
      _cancelSessionScopedWork();
      _cancelTimersOnDispose();
      _disposeFocusNodesOnDispose();
      _removeOverlayEntriesOnDispose();
      _disposePlayersOnDispose();
      try {
        VolumeController.instance.removeListener();
      } catch (_) { /* ignore */ }
      _disposeBrightnessVolume();
    } catch (e) { /* ignore */ }
    try {
      PlaybackWakelockService.instance.release().ignore();
    } catch (_) { /* ignore */ }

    try {
      // Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ™â€¡Ã˜Â§Ã˜ÂªÃ™Â Ã™â€ Ã˜Â®Ã™â€žÃ™Å  Ã˜Â§Ã™â€žÃ™â‚¬ orientation landscape Ã˜Â«Ã˜Â§Ã˜Â¨Ã˜Âª Ã˜Â­Ã˜ÂªÃ™â€° Ã˜Â¨Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â®Ã˜Â±Ã™Ë†Ã˜Â¬ Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ™â€žÃ˜Â§Ã˜Â¹Ã˜Â¨.
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) { /* ignore */ }

    try {
      _positionVN.dispose();
      _durationVN.dispose();
      _sliderVN.dispose();
      _validPositionVN.dispose();
      _maxDurationVN.dispose();
      _bufferVN.dispose();
    } catch (_) { /* ignore */ }
    unawaited(_applyPlaybackVolumeForIptvOverlay(ducked: false));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PlaybackWakelockService.instance
          .acquire(title: widget.title, isLive: widget.isLive)
          .ignore();
      if (!mounted) return;
      if (!_isInPipMode) {
        changeDeviceOrient();
        unawaited(lockHomeScreenLandscape());
      }
      if (isPlayed || _wasPlayingBeforePip) {
        try {
          if (_useExo) {
            _exoController?.play();
          } else {
            _videoPlayerController?.play();
          }
        } catch (_) { /* ignore */ }
      }
      // Exo + VLC: بعد العودة من الخلفية أعد تقييم الستريم (جلسة طويلة قد تموت بصمت).
      if (widget.isLive && !_userRequestedLivePause) {
        _startLiveKeepAliveWatchdog();
        if (_useExo) {
          final v = _exoController?.videoPlayerController?.value;
          final dead = v == null ||
              v.hasError ||
              (!v.isPlaying && !v.isBuffering);
          if (dead) {
            // جلسة ميتة (شاشة سوداء / توقف): أعد الاتصال فوراً.
            _liveHadHealthyPlayback = true;
            _scheduleLiveReconnect(immediate: true);
          } else {
            _evaluateLiveKeepAlive();
          }
        } else {
          _resetLiveKeepAliveState();
          _seedLiveKeepAliveHeartbeat();
          _evaluateLiveKeepAlive();
        }
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      try {
        _persistLastLiveChannel();
      } catch (_) { /* ignore */ }
      if (_isInPipMode || _enteringPipMode) return;
      if (!widget.isLive) {
        try {
          if (_useExo) {
            _exoController?.pause();
          } else {
            _videoPlayerController?.pause();
          }
        } catch (_) { /* ignore */ }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLiveChannel = _currentLiveChannel ?? widget.channelLive;
    final liveName =
        effectiveLiveChannel?.name ??
        ((widget.startInIptvBrowser && effectiveLiveChannel == null)
            ? ''
            : widget.title);

    // Avoid focus churn: do not request focus from build/postFrameCallback on
    // every frame; overlays already call requestFocus when they close.

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (_awaitingResumeChoice) {
          // لا تحفظ موضعاً صفرياً فيمحو آخر تقدّم — أغلق بدون نتيجة.
          if (!didPop) {
            try {
              Navigator.of(context).pop();
            } catch (e) { /* ignore */ }
          }
          return;
        }
        if (_vodLockConsumeNextBack || _vodLockWithinBackUnlockGrace()) {
          _vodLockConsumeNextBack = false;
          return;
        }
        if (_vodLockActive) {
          if (!didPop) {
            _showVodLockHoldHint();
          }
          return;
        }
        if (_showEpisodeSuggestionsOverlay) {
          _closeEpisodeOverlay();
          return;
        }
        if (_showMovieSuggestionsOverlay) {
          _closeMovieOverlay();
          return;
        }
        if (_showLiveChannelSuggestionsOverlay) {
          _closeLiveChannelOverlay();
          return;
        }
        if (_showLiveIptvOverlay) {
          if (widget.startInIptvBrowser) {
            _exitLiveBrowserToHome();
          } else {
            _closeLiveIptvOverlay();
          }
          return;
        }

        if (widget.isLive && widget.startInIptvBrowser) {
          _openLiveIptvOverlay();
          return;
        }
        if (!didPop) _popWithResult();
      },
      child: Scaffold(
        backgroundColor: widget.startInIptvBrowser
            ? const Color(0xFF141824)
            : Colors.black,
        body: Focus(
          focusNode: _rootPlayerFocusNode,

          autofocus: !_awaitingResumeChoice && !_showLiveIptvOverlay,
          canRequestFocus: !_awaitingResumeChoice && !_showLiveIptvOverlay,
          skipTraversal: _awaitingResumeChoice || _showLiveIptvOverlay,
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (ModalRoute.of(context)?.isCurrent != true) {
              return KeyEventResult.ignored;
            }

            final key = event.logicalKey;

            if (_vodLockActive && !widget.isLive) {
              return KeyEventResult.handled;
            }

            final isOk = _isOkLogicalKey(key);

            if (_awaitingResumeChoice) {
              return KeyEventResult.ignored;
            }

            if (_showEpisodeSuggestionsOverlay) {
              if (event is KeyDownEvent &&
                  (key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.browserBack)) {
                _closeEpisodeOverlay();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }

            if (_showMovieSuggestionsOverlay) {
              if (event is KeyDownEvent &&
                  (key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.browserBack)) {
                _closeMovieOverlay();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }

            if (_showLiveChannelSuggestionsOverlay) {
              if (event is KeyDownEvent &&
                  (key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.browserBack)) {
                _closeLiveChannelOverlay();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }

            if (_showLiveIptvOverlay) {
              if (event is KeyDownEvent &&
                  (key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.browserBack)) {
                if (widget.startInIptvBrowser) {
                  _exitLiveBrowserToHome();
                } else {
                  _closeLiveIptvOverlay();
                }
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }

            if (widget.isLive &&
                widget.startInIptvBrowser &&
                event is KeyDownEvent &&
                (key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.browserBack)) {
              _openLiveIptvOverlay();
              return KeyEventResult.handled;
            }

            if (isOk) {
              return _handleOkKeyEvent(event);
            }

            if (event is KeyDownEvent) {
              final res = _handleKeyDownEvent(key);
              if (res != KeyEventResult.ignored) return res;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            key: _playerVideoStackKey,
            alignment: Alignment.bottomCenter,
            children: [
              if (!_showLiveIptvOverlay)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_vodLockActive) return;
                    // Swipe just opened/closed suggestions — don't also toggle chrome.
                    if (_suggestionSwipeJustHandled) return;
                    setState(() {
                      showControllersVideo = !showControllersVideo;
                      if (!showControllersVideo) {
                        _dismissBvIntro();
                      }
                    });
                    if (showControllersVideo) {
                      _schedulePlayerControlsHideAfterIdle();
                    } else {
                      _cancelPlayerControlsHideTimer();
                      _releaseToolbarFocusToPlayer();
                    }
                  },
                  onDoubleTapDown: (details) {
                    if (_vodLockActive) return;
                    if (widget.isLive && widget.channelLive != null) {
                      _openLiveIptvOverlay();
                      return;
                    }
                    final canSeek = !widget.isLive;
                    if (!canSeek) return;
                    final w = MediaQuery.of(context).size.width;
                    _handleRapidDoubleTapSeek(details.localPosition, w);
                  },
                  onVerticalDragStart: _onBvVerticalDragStart,
                  onVerticalDragUpdate: _onBvVerticalDragUpdate,
                  onVerticalDragCancel: _onBvVerticalDragCancel,
                  onVerticalDragEnd: (details) {
                    if (_vodLockActive) return;
                    _onBvVerticalDragEnd(details);
                  },
                  child: Container(
                    width: getSize(context).width,
                    height: getSize(context).height,
                    color: Colors.black,
                    // Exo/VLC live in positioned layers below so opening the
                    // IPTV panel never remounts the player (avoids black screen).
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),

              // مثل المشروع القديم: اللوحة أولاً ثم المشغّل فوق خانة المصغّr.
              if (_showLiveIptvOverlay && widget.isLive)
                _iptvBrowserUiReady
                    ? _buildLiveIptvSplitLayout(liveName: liveName)
                    : const Positioned.fill(
                        child: ColoredBox(color: Color(0xFF141824)),
                      ),

              if (_useExo && _exoController != null)
                _buildExoPositionedPlayerLayer(),

              if (!_useExo && _videoPlayerController != null)
                _buildVlcPositionedPlayerLayer(),

              // Brightness/volume UI — never while the side panel is open.
              if (!_showLiveIptvOverlay) _buildBrightnessDimOverlay(),

              if (_vodScrubReleaseLoading && !widget.isLive)
                Center(
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      color: kColorPrimary,
                      strokeWidth: 4,
                    ),
                  ),
                ),

              // تلميح فتح قائمة الأفلام/الحلقات/القنوات (مرة واحدة)
              if ((_isMovieStyle || _isSeriesStyle) && _showMovieDownHint)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).padding.bottom + 28,
                  child: _MovieDownHintWidget(
                    forEpisodes: _isSeriesStyle,
                    onDismiss: () {
                      if (mounted) setState(() => _showMovieDownHint = false);
                    },
                  ),
                ),
              if (widget.isLive && _isLiveFullscreenPlayer && _showLiveDownHint)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).padding.bottom + 28,
                  child: _MovieDownHintWidget(
                    forLive: true,
                    onDismiss: () {
                      if (mounted) setState(() => _showLiveDownHint = false);
                    },
                  ),
                ),

              // غطاء أسود يخفي بقايا المصغّر فقط (تحت التحكم).
              if (widget.isLive &&
                  !_showLiveIptvOverlay &&
                  (_iptvSurfaceTransitionCover ||
                      _isSwitchingLiveChannel ||
                      _vlcParkOffscreen))
                const Positioned.fill(
                  child: IgnorePointer(child: ColoredBox(color: Colors.black)),
                ),

              if (widget.isLive &&
                  !_showLiveIptvOverlay &&
                  !(_showMovieSuggestionsOverlay ||
                      _showEpisodeSuggestionsOverlay ||
                      _showLiveChannelSuggestionsOverlay))
                Positioned.fill(
                  child: _buildLivePlayerControlsOverlay(liveName: liveName),
                ),

              if (!widget.isLive &&
                  !(_showMovieSuggestionsOverlay ||
                      _showEpisodeSuggestionsOverlay))
                Positioned.fill(child: _buildVodPlayerControlsOverlay()),

              if (_useExo &&
                  (_showPlayerLoadingOverlay ||
                      (widget.isLive &&
                          !_showLiveIptvOverlay &&
                          (_iptvSurfaceTransitionCover ||
                              _isSwitchingLiveChannel ||
                              _vlcParkOffscreen))))
                _buildPlayerBufferingOverlay(
                  forceFullscreenCover:
                      !_showLiveIptvOverlay &&
                      (_iptvSurfaceTransitionCover ||
                          _isSwitchingLiveChannel ||
                          _vlcParkOffscreen),
                  spinnerOnly: true,
                ),

              if (_showSeekForwardHint ||
                  _showSeekBackwardHint ||
                  _showSeekLoading)
                SizedBox.expand(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_showSeekLoading)
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 3.5,
                            color: kColorPrimary,
                          ),
                        ),
                      if (_showSeekBackwardHint)
                        Positioned(
                          left: 40,
                          child: _buildSeekHint(-_backwardSeekHintSeconds),
                        ),
                      if (_showSeekForwardHint)
                        Positioned(
                          right: 40,
                          child: _buildSeekHint(_forwardSeekHintSeconds),
                        ),
                    ],
                  ),
                ),

              if (!_showLiveIptvOverlay) _buildBrightnessVolumeOverlay(),

              // When the bottom lists are visible, allow touch on the list itself,
              // but tapping the rest of the screen dismisses the list.
              if (_showMovieSuggestionsOverlay ||
                  _showEpisodeSuggestionsOverlay ||
                  (_isLiveFullscreenPlayer &&
                      _showLiveChannelSuggestionsOverlay))
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_showMovieSuggestionsOverlay) {
                        _closeMovieOverlay();
                      }
                      if (_showEpisodeSuggestionsOverlay) {
                        _closeEpisodeOverlay();
                      }
                      if (_showLiveChannelSuggestionsOverlay) {
                        _closeLiveChannelOverlay();
                      }
                    },
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity > 200) {
                        if (_showMovieSuggestionsOverlay) {
                          _closeMovieOverlay();
                        }
                        if (_showEpisodeSuggestionsOverlay) {
                          _closeEpisodeOverlay();
                        }
                        if (_showLiveChannelSuggestionsOverlay) {
                          _closeLiveChannelOverlay();
                        }
                      }
                    },
                  ),
                ),

              // Ã™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â© Ã˜Â­Ã™â€žÃ™â€šÃ˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã™â€žÃ˜Â³Ã™â€ž
              if (_isSeriesStyle &&
                  widget.serieEpisodes != null &&
                  widget.serieEpisodes!.isNotEmpty)
                Offstage(
                  offstage: !_showEpisodeSuggestionsOverlay,
                  child: _EpisodeSuggestionsOverlay(
                    key: _episodeOverlayKey,
                    focusNode: _episodeOverlayFocusNode,
                    isVisible: _showEpisodeSuggestionsOverlay,
                    topClipPadding: MediaQuery.of(context).padding.top + 140,
                    episodes: widget.serieEpisodes!,
                    currentEpisodeId: _currentEpisodeId,
                    userAuth: widget.serieUserAuth,
                    channelSerie: widget.channelSerie,
                    onEpisodeSelected: (episode, link) {
                      _closeEpisodeOverlay();
                      _switchToEpisode(episode, link);
                    },
                    onDismiss: _closeEpisodeOverlay,
                  ),
                ),

              // Ã™â€šÃ˜Â§Ã˜Â¦Ã™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â£Ã™ÂÃ™â€žÃ˜Â§Ã™â€¦ Ã˜Â§Ã™â€žÃ™â€¦Ã™â€šÃ˜ÂªÃ˜Â±Ã˜Â­Ã˜Â© Ã¢â‚¬â€œ Offstage Ã™Å Ã˜Â¨Ã™â€šÃ™Å Ã™â€¡Ã˜Â§ Ã˜Â­Ã™Å Ã˜Â© Ã˜Â¯Ã˜Â§Ã˜Â¦Ã™â€¦Ã˜Â§Ã™â€¹ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â¬Ã˜Â±Ã˜Â©
              // Ã˜Â­Ã˜ÂªÃ™â€° Ã™â€žÃ˜Â§ Ã™Å Ã™ÂÃ˜Â¹Ã˜Â§Ã˜Â¯ Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã˜Â§Ã™â€žÃ™â‚¬ State Ã˜Â¹Ã™â€ Ã˜Â¯ Ã™Æ’Ã™â€ž setState Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜ÂºÃ™â€ž
              if (_isMovieStyle)
                Offstage(
                  offstage: !_showMovieSuggestionsOverlay,
                  child: _MovieSuggestionsOverlay(
                    key: _movieOverlayKey,
                    focusNode: _movieOverlayFocusNode,
                    isVisible: _showMovieSuggestionsOverlay,
                    topClipPadding: MediaQuery.of(context).padding.top + 140,
                    currentMovie: _currentMovie ?? widget.channelMovie,
                    userAuth: context.read<AuthBloc>().state is AuthSuccess
                        ? (context.read<AuthBloc>().state as AuthSuccess).user
                        : null,
                    onMovieSelected: (movie, link) {
                      _closeMovieOverlay();
                      _switchToMovie(movie, link);
                    },
                    onDismiss: _closeMovieOverlay,
                  ),
                ),

              if (widget.isLive && _isLiveFullscreenPlayer)
                Offstage(
                  offstage: !_showLiveChannelSuggestionsOverlay,
                  child: _LiveChannelSuggestionsOverlay(
                    key: _liveChannelOverlayKey,
                    focusNode: _liveChannelOverlayFocusNode,
                    isVisible: _showLiveChannelSuggestionsOverlay,
                    channelsProvider: _liveZapChannelList,
                    currentChannel: _currentLiveChannel ?? widget.channelLive,
                    focusIndex: _liveZapCurrentIndex(),
                    onChannelSelected: (channel) {
                      unawaited(_selectLiveChannelFromOverlay(channel));
                    },
                    onDismiss: _closeLiveChannelOverlay,
                  ),
                ),

              // IPTV split layout replaces the old fullscreen overlay layer.
              if (_awaitingResumeChoice)
                Positioned.fill(
                  child: ResumePlaybackDialog(
                    positionSeconds: _pendingResumeSeconds,
                    onContinue: _onResumePlaybackContinue,
                    onRestart: _onResumePlaybackRestart,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toast Ã™ÂÃ™Ë†Ã™â€š Ã˜Â§Ã™â€žÃ™ÂÃ™Å Ã˜Â¯Ã™Å Ã™Ë†: Ã˜Â¸Ã™â€¡Ã™Ë†Ã˜Â± + Ã˜Â«Ã˜Â¨Ã˜Â§Ã˜Âª + Ã˜Â§Ã˜Â®Ã˜ÂªÃ™ÂÃ˜Â§Ã˜Â¡ Ã˜Â®Ã™â€žÃ˜Â§Ã™â€ž ~Ã™Â¢ Ã˜Â«Ã˜Â§Ã™â€ Ã™Å Ã˜Â© (Ã™â€¦Ã™â€ Ã˜Â§Ã˜Â³Ã˜Â¨ Ã™â€žÃ˜ÂªÃ˜Â¨Ã˜Â¯Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜ÂºÃ™â€˜Ã™â€ž).
