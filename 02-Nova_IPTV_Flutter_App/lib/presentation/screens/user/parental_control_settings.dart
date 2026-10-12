part of '../screens.dart';

/// حماية شاشة مقفولة بالرقابة الأبوية — يطلب PIN عند الدخول.
mixin ParentalSectionGateMixin<T extends StatefulWidget> on State<T> {
  bool _parentalGateChecking = true;
  bool _parentalGateUnlocked = false;

  ParentalSection get parentalGateSection;

  /// شلّ التلفزيون يمرّ عبر PIN قبل التبديل — لا تُعد الطلب ولا Get.back().
  bool get skipParentalGateOnInit => false;

  @override
  void initState() {
    super.initState();
    if (skipParentalGateOnInit) {
      _parentalGateChecking = false;
      _parentalGateUnlocked = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _runParentalGate());
  }

  Future<void> _runParentalGate() async {
    final service = ParentalControlService.instance;
    if (!service.isSectionLocked(parentalGateSection)) {
      if (!mounted) return;
      setState(() {
        _parentalGateChecking = false;
        _parentalGateUnlocked = true;
      });
      return;
    }

    final ok = await service.requestSectionAccess(context, parentalGateSection);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _parentalGateChecking = false;
        _parentalGateUnlocked = true;
      });
    } else {
      Get.back();
    }
  }

  Widget buildWithParentalGate(Widget child) {
    if (_parentalGateChecking) {
      return Scaffold(
        body: Ink(
          width: 100.w,
          height: 100.h,
          decoration: kDecorBackground,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!_parentalGateUnlocked) {
      return const SizedBox.shrink();
    }
    return child;
  }
}

/// قسم الرقابة الأبوية داخل الإعدادات.
class _ParentalControlSettingsCard extends StatefulWidget {
  const _ParentalControlSettingsCard({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_ParentalControlSettingsCard> createState() =>
      _ParentalControlSettingsCardState();
}

class _ParentalControlSettingsCardState
    extends State<_ParentalControlSettingsCard> {
  final ParentalControlService _service = ParentalControlService.instance;

  final FocusNode _enableFocusNode = FocusNode();
  final FocusNode _lockLiveFocusNode = FocusNode();
  final FocusNode _lockMoviesFocusNode = FocusNode();
  final FocusNode _lockSeriesFocusNode = FocusNode();
  final FocusNode _lockSettingsFocusNode = FocusNode();
  final FocusNode _hideAdultFocusNode = FocusNode();
  final FocusNode _changePinFocusNode = FocusNode();

  bool _enableFocused = false;
  bool _lockLiveFocused = false;
  bool _lockMoviesFocused = false;
  bool _lockSeriesFocused = false;
  bool _lockSettingsFocused = false;
  bool _hideAdultFocused = false;
  bool _changePinFocused = false;

  Future<void> _onEnableChanged(bool value) async {
    if (value) {
      if (!_service.hasPin) {
        final setupOk = await showParentalPinSetupFlow(context);
        if (setupOk != true || !mounted) return;
      } else {
        await _service.enableWithExistingPin();
      }
      if (!mounted) return;
      showSoftToast(
        context,
        'parental_enabled_title'.tr,
        'parental_enabled_msg'.tr,
      );
    } else {
      final ok = await showParentalPinDialog(
        context,
        title: 'parental_disable_title'.tr,
        subtitle: 'parental_disable_sub'.tr,
      );
      if (ok != true || !mounted) return;
      await _service.disableParentalControl(
        ParentalPinSessionHolder.lastVerifiedPin,
      );
      if (!mounted) return;
      // أزل التركيز عن الخيارات الفرعية حتى لا تبقى عالقة على التلفاز
      _lockLiveFocusNode.unfocus();
      _lockMoviesFocusNode.unfocus();
      _lockSeriesFocusNode.unfocus();
      _lockSettingsFocusNode.unfocus();
      _hideAdultFocusNode.unfocus();
      _changePinFocusNode.unfocus();
      showInfoToast(
        context,
        'parental_disabled_title'.tr,
        'parental_disabled_msg'.tr,
      );
    }
    widget.onChanged();
  }

  void _toastLockChange(String sectionName, bool enabled) {
    if (!mounted) return;
    if (enabled) {
      showSoftToast(
        context,
        'parental_section_title'.tr,
        'parental_lock_enabled_msg'.trParams({'name': sectionName}),
      );
    } else {
      showInfoToast(
        context,
        'parental_section_title'.tr,
        'parental_lock_disabled_msg'.trParams({'name': sectionName}),
      );
    }
  }

  Future<void> _onChangePin() async {
    if (!_service.isEnabled || !_service.hasPin) return;
    final ok = await showParentalPinChangeFlow(context);
    if (ok == true && mounted) {
      showSoftToast(
        context,
        'parental_section_title'.tr,
        'parental_pin_changed'.tr,
      );
      widget.onChanged();
    }
  }

  @override
  void dispose() {
    _enableFocusNode.dispose();
    _lockLiveFocusNode.dispose();
    _lockMoviesFocusNode.dispose();
    _lockSeriesFocusNode.dispose();
    _lockSettingsFocusNode.dispose();
    _hideAdultFocusNode.dispose();
    _changePinFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _service.isEnabled;
    final tv = isTv(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(
          icon: FontAwesomeIcons.lock,
          label: 'parental_section_title'.tr,
        ),
        _SettingsCard(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ParentalEnableTile(
                focusNode: _enableFocusNode,
                focused: _enableFocused,
                onFocusChange: (v) {
                  if (_enableFocused != v) setState(() => _enableFocused = v);
                },
                tvFocusOrder: tv ? 20 : null,
                value: enabled,
                onChanged: _onEnableChanged,
              ),
              const SizedBox(height: 6),
              _ParentalLocksGrid(
                interactive: enabled,
                tiles: [
                  _ParentalLockSpec(
                    focusNode: _lockLiveFocusNode,
                    focused: _lockLiveFocused,
                    onFocusChange: (v) {
                      if (_lockLiveFocused != v) {
                        setState(() => _lockLiveFocused = v);
                      }
                    },
                    tvFocusOrder: tv && enabled ? 21 : null,
                    icon: FontAwesomeIcons.tv,
                    title: 'parental_lock_live'.tr,
                    value: _service.lockLive,
                    onChanged: (v) {
                      if (!enabled) return;
                      _service.setLockLive(v);
                      _toastLockChange('parental_lock_live'.tr, v);
                      widget.onChanged();
                    },
                  ),
                  _ParentalLockSpec(
                    focusNode: _lockMoviesFocusNode,
                    focused: _lockMoviesFocused,
                    onFocusChange: (v) {
                      if (_lockMoviesFocused != v) {
                        setState(() => _lockMoviesFocused = v);
                      }
                    },
                    tvFocusOrder: tv && enabled ? 22 : null,
                    icon: FontAwesomeIcons.clapperboard,
                    title: 'parental_lock_movies'.tr,
                    value: _service.lockMovies,
                    onChanged: (v) {
                      if (!enabled) return;
                      _service.setLockMovies(v);
                      _toastLockChange('parental_lock_movies'.tr, v);
                      widget.onChanged();
                    },
                  ),
                  _ParentalLockSpec(
                    focusNode: _lockSeriesFocusNode,
                    focused: _lockSeriesFocused,
                    onFocusChange: (v) {
                      if (_lockSeriesFocused != v) {
                        setState(() => _lockSeriesFocused = v);
                      }
                    },
                    tvFocusOrder: tv && enabled ? 23 : null,
                    icon: FontAwesomeIcons.layerGroup,
                    title: 'parental_lock_series'.tr,
                    value: _service.lockSeries,
                    onChanged: (v) {
                      if (!enabled) return;
                      _service.setLockSeries(v);
                      _toastLockChange('parental_lock_series'.tr, v);
                      widget.onChanged();
                    },
                  ),
                  _ParentalLockSpec(
                    focusNode: _lockSettingsFocusNode,
                    focused: _lockSettingsFocused,
                    onFocusChange: (v) {
                      if (_lockSettingsFocused != v) {
                        setState(() => _lockSettingsFocused = v);
                      }
                    },
                    tvFocusOrder: tv && enabled ? 24 : null,
                    icon: FontAwesomeIcons.gear,
                    title: 'parental_lock_settings'.tr,
                    value: _service.lockSettings,
                    onChanged: (v) {
                      if (!enabled) return;
                      _service.setLockSettings(v);
                      _toastLockChange('parental_lock_settings'.tr, v);
                      widget.onChanged();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _ParentalSlimLockTile(
                      interactive: enabled,
                      spec: _ParentalLockSpec(
                        focusNode: _hideAdultFocusNode,
                        focused: _hideAdultFocused,
                        onFocusChange: (v) {
                          if (_hideAdultFocused != v) {
                            setState(() => _hideAdultFocused = v);
                          }
                        },
                        tvFocusOrder: tv && enabled ? 25 : null,
                        icon: FontAwesomeIcons.eyeSlash,
                        title: 'parental_hide_adult'.tr,
                        value: _service.hideAdultCategories,
                        onChanged: (v) {
                          if (!enabled) return;
                          _service.setHideAdultCategories(v);
                          if (mounted) {
                            if (v) {
                              showSoftToast(
                                context,
                                'parental_section_title'.tr,
                                'parental_hide_adult_enabled_msg'.tr,
                              );
                            } else {
                              showInfoToast(
                                context,
                                'parental_section_title'.tr,
                                'parental_hide_adult_disabled_msg'.tr,
                              );
                            }
                          }
                          widget.onChanged();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ParentalChangePinChip(
                      interactive: enabled,
                      focusNode: _changePinFocusNode,
                      focused: _changePinFocused,
                      onFocusChange: (v) {
                        if (_changePinFocused != v) {
                          setState(() => _changePinFocused = v);
                        }
                      },
                      tvFocusOrder: tv && enabled ? 26 : null,
                      onTap: _onChangePin,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ParentalEnableTile extends StatelessWidget {
  const _ParentalEnableTile({
    required this.focusNode,
    required this.focused,
    required this.onFocusChange,
    this.tvFocusOrder,
    required this.value,
    required this.onChanged,
  });

  final FocusNode focusNode;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final int? tvFocusOrder;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);

    Widget tile = Actions(
      actions:
          tv
              ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (ActivateIntent intent) {
                    onChanged(!value);
                    return null;
                  },
                ),
              }
              : const {},
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          onFocusChange(v);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient:
                value
                    ? LinearGradient(
                      colors: [
                        kColorPrimary.withValues(alpha: 0.18),
                        kColorPrimaryDark.withValues(alpha: 0.1),
                      ],
                    )
                    : null,
            color: value ? null : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color:
                  showFocus
                      ? kColorPrimary
                      : (value
                          ? kColorPrimary.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.1)),
              width: showFocus ? 2 : 1,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: kColorPrimary.withValues(alpha: 0.18),
                  border: Border.all(
                    color: kColorPrimary.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  FontAwesomeIcons.shieldHalved,
                  color: kColorPrimary,
                  size: 14,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'parental_enable'.tr,
                      style: Get.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'parental_enable_sub'.tr,
                      style: Get.textTheme.labelSmall?.copyWith(
                        color: Colors.white54,
                        height: 1.2,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeTrackColor: kColorPrimary.withValues(alpha: 0.45),
                activeThumbColor: kColorPrimary,
                inactiveTrackColor: Colors.white24,
                inactiveThumbColor: Colors.white54,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );

    if (tv && tvFocusOrder != null) {
      tile = FocusTraversalOrder(
        order: NumericFocusOrder(tvFocusOrder!.toDouble()),
        child: tile,
      );
    }
    return tile;
  }
}

class _ParentalLockSpec {
  const _ParentalLockSpec({
    required this.focusNode,
    required this.focused,
    required this.onFocusChange,
    this.tvFocusOrder,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final FocusNode focusNode;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final int? tvFocusOrder;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
}

class _ParentalLocksGrid extends StatelessWidget {
  const _ParentalLocksGrid({
    required this.tiles,
    this.interactive = true,
  });

  final List<_ParentalLockSpec> tiles;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final left = tiles[i];
      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < tiles.length ? 6 : 0),
          child: Row(
            children: [
              Expanded(
                child: _ParentalSlimLockTile(
                  interactive: interactive,
                  spec: left,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child:
                    right == null
                        ? const SizedBox.shrink()
                        : _ParentalSlimLockTile(
                          interactive: interactive,
                          spec: right,
                        ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _ParentalSlimLockTile extends StatelessWidget {
  const _ParentalSlimLockTile({
    required this.spec,
    this.interactive = true,
  });

  final _ParentalLockSpec spec;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus =
        interactive && settingsShowFocusDecor(context, spec.focused);
    final value = spec.value;
    final muted = !interactive;

    Widget tile = Actions(
      actions:
          tv && interactive
              ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (ActivateIntent intent) {
                    spec.onChanged(!value);
                    return null;
                  },
                ),
              }
              : const {},
      child: Focus(
        focusNode: spec.focusNode,
        canRequestFocus: interactive,
        skipTraversal: !interactive,
        onFocusChange: (v) {
          if (!interactive) return;
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          spec.onFocusChange(v);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors:
                  muted
                      ? [
                        Colors.black.withValues(alpha: 0.42),
                        Colors.black.withValues(alpha: 0.28),
                      ]
                      : value
                      ? [
                        kColorPrimary.withValues(alpha: 0.2),
                        kColorPrimary.withValues(alpha: 0.06),
                      ]
                      : [
                        Colors.white.withValues(alpha: 0.05),
                        Colors.white.withValues(alpha: 0.02),
                      ],
            ),
            border: Border.all(
              color:
                  showFocus
                      ? kColorPrimary
                      : muted
                      ? Colors.white.withValues(alpha: 0.05)
                      : (value
                          ? kColorPrimary.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.1)),
              width: showFocus ? 1.6 : 1,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
          ),
          child: Opacity(
            opacity: muted ? 0.38 : 1,
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: kColorPrimary.withValues(
                      alpha: muted ? 0.08 : (value ? 0.22 : 0.12),
                    ),
                  ),
                  child: Icon(
                    spec.icon,
                    color: muted ? Colors.white38 : kColorPrimary,
                    size: 12,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    spec.title,
                    style: Get.textTheme.labelSmall?.copyWith(
                      color: muted ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: Switch.adaptive(
                    value: value,
                    onChanged: interactive ? spec.onChanged : null,
                    activeTrackColor: kColorPrimary.withValues(alpha: 0.45),
                    activeThumbColor: kColorPrimary,
                    inactiveTrackColor: Colors.white24,
                    inactiveThumbColor: Colors.white54,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tv && interactive && spec.tvFocusOrder != null) {
      tile = FocusTraversalOrder(
        order: NumericFocusOrder(spec.tvFocusOrder!.toDouble()),
        child: tile,
      );
    }
    return tile;
  }
}

class _ParentalChangePinChip extends StatelessWidget {
  const _ParentalChangePinChip({
    required this.focusNode,
    required this.focused,
    required this.onFocusChange,
    this.tvFocusOrder,
    required this.onTap,
    this.interactive = true,
  });

  final FocusNode focusNode;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final int? tvFocusOrder;
  final VoidCallback onTap;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus =
        interactive && settingsShowFocusDecor(context, focused);
    final muted = !interactive;

    Widget chip = Focus(
      focusNode: focusNode,
      canRequestFocus: interactive,
      skipTraversal: !interactive,
      onFocusChange: (v) {
        if (!interactive) return;
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        onFocusChange(v);
      },
      onKeyEvent:
          tv && interactive
              ? (node, event) => settingsTvActivateOnSelect(event, onTap)
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors:
                muted
                    ? [
                      Colors.black.withValues(alpha: 0.42),
                      Colors.black.withValues(alpha: 0.28),
                    ]
                    : [
                      kColorPrimary.withValues(alpha: 0.18),
                      kColorPrimary.withValues(alpha: 0.06),
                    ],
          ),
          border: Border.all(
            color:
                showFocus
                    ? kColorPrimary
                    : muted
                    ? Colors.white.withValues(alpha: 0.05)
                    : kColorPrimary.withValues(alpha: 0.4),
            width: showFocus ? 1.6 : 1,
          ),
          boxShadow: settingsThemedFocusGlow(showFocus),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap:
                interactive
                    ? () {
                      settingsReleaseTouchFocus(context);
                      onTap();
                    }
                    : null,
            child: Opacity(
              opacity: muted ? 0.38 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: kColorPrimary.withValues(
                          alpha: muted ? 0.08 : 0.2,
                        ),
                      ),
                      child: Icon(
                        FontAwesomeIcons.key,
                        color: muted ? Colors.white38 : kColorPrimary,
                        size: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'parental_change_pin'.tr,
                        style: Get.textTheme.labelMedium?.copyWith(
                          color: muted ? Colors.white38 : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? FontAwesomeIcons.chevronLeft
                          : FontAwesomeIcons.chevronRight,
                      size: 11,
                      color: Colors.white38,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (tv && interactive && tvFocusOrder != null) {
      chip = settingsTvTraversalOrder(
        context,
        order: tvFocusOrder!.toDouble(),
        child: chip,
      );
    }
    return chip;
  }
}
