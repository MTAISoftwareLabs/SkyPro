part of '../screens.dart';

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: kColorPrimary.withValues(alpha: 0.95), size: 13),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: Get.textTheme.labelSmall!.copyWith(
              color: Colors.white54,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kColorCardLight.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// مجموعة إعدادات بأسلوب التطبيقات الحديثة: صفوف مفصولة بخطوط رفيعة.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.titleIcon,
    required this.title,
    required this.children,
  });

  final IconData titleIcon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final items = children.whereType<Widget>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(icon: titleIcon, label: title),
        _SettingsCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 48,
                    endIndent: 10,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                items[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsIconBadge extends StatelessWidget {
  const _SettingsIconBadge({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? kColorPrimary;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0.12)],
        ),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: c, size: 13),
    );
  }
}

class _SettingsMiniPicker extends StatefulWidget {
  const _SettingsMiniPicker({
    required this.icon,
    required this.label,
    required this.value,
    this.valueIcon,
    this.tvFocusOrder,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? valueIcon;
  final num? tvFocusOrder;
  final VoidCallback onTap;

  @override
  State<_SettingsMiniPicker> createState() => _SettingsMiniPickerState();
}

class _SettingsMiniPickerState extends State<_SettingsMiniPicker> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, _focused);

    Widget tile = settingsTvTileFocus(
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        if (_focused != v) setState(() => _focused = v);
      },
      onKeyEvent:
          tv
              ? (node, event) => settingsTvActivateOnSelect(event, widget.onTap)
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              showFocus
                  ? kColorPrimary.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.02),
            ],
          ),
          border: Border.all(
            color:
                showFocus ? kColorPrimary : Colors.white.withValues(alpha: 0.1),
            width: showFocus ? 1.5 : 1,
          ),
          boxShadow: settingsThemedFocusGlow(showFocus),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              settingsReleaseTouchFocus(context);
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _SettingsIconBadge(icon: widget.icon),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: Get.textTheme.labelSmall?.copyWith(
                            color: Colors.white54,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      if (widget.valueIcon != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: widget.valueIcon!,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          widget.value,
                          style: Get.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? FontAwesomeIcons.chevronLeft
                            : FontAwesomeIcons.chevronRight,
                        size: 10,
                        color: Colors.white38,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (tv && widget.tvFocusOrder != null) {
      tile = FocusTraversalOrder(
        order: NumericFocusOrder(widget.tvFocusOrder!.toDouble()),
        child: tile,
      );
    }
    return tile;
  }
}

class _SettingsPickerTile extends StatefulWidget {
  const _SettingsPickerTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueIcon,
    this.focusNode,
    this.onFocusChange,
    this.tvFocusOrder,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? valueIcon;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final num? tvFocusOrder;
  final VoidCallback onTap;

  @override
  State<_SettingsPickerTile> createState() => _SettingsPickerTileState();
}

class _SettingsPickerTileState extends State<_SettingsPickerTile> {
  bool _focused = false;

  bool get _hasFocus => widget.focusNode?.hasFocus ?? _focused;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, _hasFocus);

    Widget tile = settingsTvTileFocus(
      focusNode: widget.focusNode,
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        widget.onFocusChange?.call(v);
        if (widget.focusNode == null && _focused != v) {
          setState(() => _focused = v);
        }
      },
      onKeyEvent:
          tv
              ? (node, event) => settingsTvActivateOnSelect(event, widget.onTap)
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color:
              showFocus
                  ? kColorPrimary.withValues(alpha: 0.12)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showFocus ? kColorPrimary : Colors.transparent,
            width: showFocus ? 1.5 : 0,
          ),
          boxShadow: settingsThemedFocusGlow(showFocus),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              settingsReleaseTouchFocus(context);
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  _SettingsIconBadge(icon: widget.icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: Get.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.valueIcon != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: widget.valueIcon!,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      widget.value,
                      textAlign: TextAlign.end,
                      style: Get.textTheme.labelMedium?.copyWith(
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
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
    );

    if (tv && widget.tvFocusOrder != null) {
      tile = FocusTraversalOrder(
        order: NumericFocusOrder(widget.tvFocusOrder!.toDouble()),
        child: tile,
      );
    }
    return tile;
  }
}

class _SettingsActionTile extends StatefulWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.focusNode,
    this.onFocusChange,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback onTap;

  @override
  State<_SettingsActionTile> createState() => _SettingsActionTileState();
}

class _SettingsActionTileState extends State<_SettingsActionTile> {
  bool _focused = false;

  bool get _hasFocus => widget.focusNode?.hasFocus ?? _focused;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, _hasFocus);
    final accent = kColorPrimary;

    Widget tile = settingsTvTileFocus(
      focusNode: widget.focusNode,
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        widget.onFocusChange?.call(v);
        if (widget.focusNode == null && _focused != v) {
          setState(() => _focused = v);
        }
      },
      onKeyEvent:
          tv
              ? (node, event) => settingsTvActivateOnSelect(event, widget.onTap)
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color:
              showFocus ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showFocus ? accent : Colors.transparent,
            width: showFocus ? 1.5 : 0,
          ),
          boxShadow: settingsThemedFocusGlow(showFocus),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              settingsReleaseTouchFocus(context);
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  _SettingsIconBadge(icon: widget.icon, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: Get.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: Get.textTheme.labelSmall?.copyWith(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
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
    );

    return tile;
  }
}

class _CompactAutoPlayTile extends StatelessWidget {
  const _CompactAutoPlayTile({
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
  final num? tvFocusOrder;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);

    Widget tile = Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            onChanged(!value);
            return null;
          },
        ),
      },
      child: settingsTvTileFocus(
        focusNode: focusNode,
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          onFocusChange(v);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color:
                showFocus
                    ? kColorPrimary.withValues(alpha: 0.12)
                    : Colors.transparent,
            border: Border.all(
              color: showFocus ? kColorPrimary : Colors.transparent,
              width: showFocus ? 1.5 : 0,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
          ),
          child: Row(
            children: [
              const _SettingsIconBadge(icon: FontAwesomeIcons.forwardStep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'settings_auto_play_next'.tr,
                  style: Get.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

class _CompactPushTile extends StatelessWidget {
  const _CompactPushTile({
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
  final num? tvFocusOrder;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);

    Widget tile = Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            onChanged(!value);
            return null;
          },
        ),
      },
      child: settingsTvTileFocus(
        focusNode: focusNode,
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          onFocusChange(v);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color:
                showFocus
                    ? kColorPrimary.withValues(alpha: 0.12)
                    : Colors.transparent,
            border: Border.all(
              color: showFocus ? kColorPrimary : Colors.transparent,
              width: showFocus ? 1.5 : 0,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
          ),
          child: Row(
            children: [
              _SettingsIconBadge(
                icon: value
                    ? FontAwesomeIcons.bell
                    : FontAwesomeIcons.bellSlash,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'settings_push_notifications'.tr,
                  style: Get.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

class _CompactRememberLastChannelTile extends StatelessWidget {
  const _CompactRememberLastChannelTile({
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
  final num? tvFocusOrder;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);

    Widget tile = Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            onChanged(!value);
            return null;
          },
        ),
      },
      child: settingsTvTileFocus(
        focusNode: focusNode,
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          onFocusChange(v);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color:
                showFocus
                    ? kColorPrimary.withValues(alpha: 0.12)
                    : Colors.transparent,
            border: Border.all(
              color: showFocus ? kColorPrimary : Colors.transparent,
              width: showFocus ? 1.5 : 0,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
          ),
          child: Row(
            children: [
              const _SettingsIconBadge(icon: FontAwesomeIcons.clockRotateLeft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'settings_remember_last_channel'.tr,
                  style: Get.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

class _CompactSubtitleLangTile extends StatelessWidget {
  const _CompactSubtitleLangTile({
    required this.focusNode,
    required this.focused,
    required this.onFocusChange,
    this.tvFocusOrder,
    required this.languageCode,
    required this.onTap,
  });

  final FocusNode focusNode;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final num? tvFocusOrder;
  final String languageCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);
    final code = languageCode.trim().toUpperCase();
    final label = SubtitleService.labelForLanguageCode(languageCode);

    Widget tile = Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            onTap();
            return null;
          },
        ),
      },
      child: settingsTvTileFocus(
        focusNode: focusNode,
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          onFocusChange(v);
        },
        onKeyEvent:
            tv
                ? (node, event) => settingsTvActivateOnSelect(event, onTap)
                : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color:
                    showFocus
                        ? kColorPrimary.withValues(alpha: 0.12)
                        : Colors.transparent,
                border: Border.all(
                  color: showFocus ? kColorPrimary : Colors.transparent,
                  width: showFocus ? 1.5 : 0,
                ),
                boxShadow: settingsThemedFocusGlow(showFocus),
              ),
              child: Row(
                children: [
                  const _SettingsIconBadge(icon: LucideIcons.captions),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'settings_default_subtitle_lang'.tr,
                          style: Get.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        colors: [
                          kColorPrimary.withValues(alpha: 0.32),
                          kColorPrimaryDark.withValues(alpha: 0.18),
                        ],
                      ),
                      border: Border.all(
                        color: kColorPrimary.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        color: kColorPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

class _CompactSubtitleStyleTile extends StatelessWidget {
  const _CompactSubtitleStyleTile({
    required this.focusNode,
    required this.focused,
    required this.onFocusChange,
    required this.appearance,
    required this.onTap,
    this.tvFocusOrder,
  });

  final FocusNode focusNode;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final SubtitleAppearance appearance;
  final VoidCallback onTap;
  final num? tvFocusOrder;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);
    final bgLabel = appearance.backgroundEnabled
        ? 'settings_subtitle_bg_on'.tr
        : 'settings_subtitle_bg_off'.tr;

    Widget tile = Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            onTap();
            return null;
          },
        ),
      },
      child: settingsTvTileFocus(
        focusNode: focusNode,
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          onFocusChange(v);
        },
        onKeyEvent:
            tv
                ? (node, event) => settingsTvActivateOnSelect(event, onTap)
                : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color:
                    showFocus
                        ? kColorPrimary.withValues(alpha: 0.12)
                        : Colors.transparent,
                border: Border.all(
                  color: showFocus ? kColorPrimary : Colors.transparent,
                  width: showFocus ? 1.5 : 0,
                ),
                boxShadow: settingsThemedFocusGlow(showFocus),
              ),
              child: Row(
                children: [
                  const _SettingsIconBadge(icon: LucideIcons.type),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'settings_subtitle_appearance'.tr,
                          style: Get.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${appearance.fontSize.round()} · $bgLabel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevron_right,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ),
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

class _LegalCompactButton extends StatelessWidget {
  const _LegalCompactButton({
    required this.tvTraversalOrder,
    required this.focusNode,
    required this.focused,
    required this.onFocusChange,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double tvTraversalOrder;
  final FocusNode focusNode;
  final bool focused;
  final ValueChanged<bool> onFocusChange;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);

    Widget btn = settingsTvTileFocus(
      focusNode: focusNode,
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        onFocusChange(v);
      },
      onKeyEvent:
          tv ? (node, event) => settingsTvActivateOnSelect(event, onTap) : null,
      child: AnimatedScale(
        scale: showFocus ? kTvFocusScale(true, 1.04) : 1.0,
        duration: kFocusAnimDuration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: kFocusAnimDuration,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color:
                showFocus
                    ? kColorPrimary.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color:
                  showFocus
                      ? kColorPrimary
                      : Colors.white.withValues(alpha: 0.1),
              width: showFocus ? 1.5 : 1,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SettingsIconBadge(icon: icon),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Get.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (tv) {
      btn = FocusTraversalOrder(
        order: NumericFocusOrder(tvTraversalOrder),
        child: btn,
      );
    }
    return btn;
  }
}

/// زر تحديث EPG مع تعبئة تقدّم خفيفة بلون الثيم أثناء التحميل.
class _EpgUpdateChip extends StatefulWidget {
  const _EpgUpdateChip({
    required this.progress,
    required this.loading,
    this.tvFocusOrder,
    required this.onTap,
  });

  final double progress;
  final bool loading;
  final num? tvFocusOrder;
  final VoidCallback onTap;

  @override
  State<_EpgUpdateChip> createState() => _EpgUpdateChipState();
}

class _EpgUpdateChipState extends State<_EpgUpdateChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, _focused);
    final fill = widget.progress.clamp(0.0, 1.0);
    final label =
        widget.loading
            ? 'settings_update_epg_started_title'.tr
            : 'settings_update_epg'.tr;

    Widget chip = Actions(
      actions:
          tv
              ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (ActivateIntent intent) {
                    if (!widget.loading) widget.onTap();
                    return null;
                  },
                ),
              }
              : const {},
      child: settingsTvTileFocus(
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          if (_focused != v) setState(() => _focused = v);
        },
        onKeyEvent:
            tv
                ? (node, event) => settingsTvActivateOnSelect(
                  event,
                  widget.loading ? () {} : widget.onTap,
                )
                : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            onTap: widget.loading
                ? null
                : () {
                  settingsReleaseTouchFocus(context);
                  widget.onTap();
                },
            borderRadius: BorderRadius.circular(11),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(
                  color:
                      showFocus
                          ? kColorPrimary
                          : Colors.white.withValues(alpha: 0.1),
                  width: showFocus ? 1.5 : 1,
                ),
                boxShadow: settingsThemedFocusGlow(showFocus),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // خلفية فارغة + تعبئة خفيفة بلون الثيم حسب التقدّم
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth * fill;
                          final isRtl = Directionality.of(context) ==
                              TextDirection.rtl;
                          return Stack(
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                top: 0,
                                bottom: 0,
                                left: isRtl ? null : 0,
                                right: isRtl ? 0 : null,
                                width: w,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: isRtl
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      end: isRtl
                                          ? Alignment.centerLeft
                                          : Alignment.centerRight,
                                      colors: [
                                        kColorPrimary.withValues(alpha: 0.22),
                                        kColorPrimary.withValues(alpha: 0.10),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          FontAwesomeIcons.calendarDays,
                          size: 14,
                          color:
                              showFocus || widget.loading
                                  ? kColorPrimary
                                  : Colors.white60,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            style: Get.textTheme.labelMedium!.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (tv && widget.tvFocusOrder != null) {
      chip = FocusTraversalOrder(
        order: NumericFocusOrder(widget.tvFocusOrder!.toDouble()),
        child: chip,
      );
    }
    return chip;
  }
}

class _OptionChip extends StatefulWidget {
  const _OptionChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.tvFocusOrder,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final num? tvFocusOrder;
  final VoidCallback onTap;

  @override
  State<_OptionChip> createState() => _OptionChipState();
}

class _OptionChipState extends State<_OptionChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final sel = widget.isSelected;
    final showFocus = settingsShowFocusDecor(context, _focused);
    Widget chip = Actions(
      actions:
          tv
              ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (ActivateIntent intent) {
                    widget.onTap();
                    return null;
                  },
                ),
              }
              : const {},
      child: settingsTvTileFocus(
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          if (_focused != v) setState(() => _focused = v);
        },
        onKeyEvent:
            tv
                ? (node, event) =>
                    settingsTvActivateOnSelect(event, widget.onTap)
                : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            onTap: () {
              settingsReleaseTouchFocus(context);
              widget.onTap();
            },
            borderRadius: BorderRadius.circular(11),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
              decoration: BoxDecoration(
                color:
                    showFocus || sel
                        ? kColorPrimary.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color:
                      showFocus
                          ? kColorPrimary
                          : Colors.white.withValues(alpha: 0.1),
                  width: showFocus ? 1.5 : 1,
                ),
                boxShadow: settingsThemedFocusGlow(showFocus),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    size: 14,
                    color: showFocus || sel ? kColorPrimary : Colors.white60,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.label,
                      style: Get.textTheme.labelMedium!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (tv && widget.tvFocusOrder != null) {
      chip = FocusTraversalOrder(
        order: NumericFocusOrder(widget.tvFocusOrder!.toDouble()),
        child: chip,
      );
    }
    return chip;
  }
}

class _LogoutButton extends StatefulWidget {
  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _focused = false;

  Future<void> _performLogout(BuildContext context) async {
    final activationApi = ActivationApi();
    final deviceId = await activationApi.getDeviceId();
    if (deviceId.isNotEmpty) {
      await activationApi.clearPlaylistUrl(deviceId);
    }
    if (!context.mounted) return;
    // الخروج من الجلسة فقط — الحسابات تبقى محفوظة؛ والعودة مباشرة لشاشة الدخول
    await AppCacheClearer.clearAllWithBlocs(context);
    if (!context.mounted) return;
    context.read<AuthBloc>().add(AuthLogOut());
    Get.offAllNamed(screenEntry);
  }

  @override
  Widget build(BuildContext context) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, _focused);
    Widget btn = Material(
      color: Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () {
          settingsReleaseTouchFocus(context);
          _performLogout(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFF5A5A).withValues(alpha: 0.22),
                const Color(0xFFE53935).withValues(alpha: 0.14),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  showFocus
                      ? kColorPrimary
                      : const Color(0xFFFF6B6B).withValues(alpha: 0.55),
              width: showFocus ? 2 : 1,
            ),
            boxShadow: settingsThemedFocusGlow(showFocus),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FontAwesomeIcons.rightFromBracket,
                size: 15,
                color: const Color(0xFFFF8A8A),
              ),
              const SizedBox(width: 8),
              Text(
                'logout'.tr,
                style: Get.textTheme.titleSmall!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    btn = Actions(
      actions:
          tv
              ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (ActivateIntent intent) {
                    _performLogout(context);
                    return null;
                  },
                ),
              }
              : const {},
      child: settingsTvTileFocus(
        onFocusChange: (v) {
          if (!tv) {
            if (v) settingsReleaseTouchFocus(context);
            return;
          }
          if (_focused != v) setState(() => _focused = v);
        },
        onKeyEvent:
            tv
                ? (node, event) => settingsTvActivateOnSelect(
                  event,
                  () => _performLogout(context),
                )
                : null,
        child: btn,
      ),
    );
    return btn;
  }
}
