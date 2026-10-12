part of '../screens.dart';

class _AccountCard extends StatefulWidget {
  const _AccountCard({this.userInfo});

  final UserModel? userInfo;

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  final FocusNode _removeAdsFocus = FocusNode(
    debugLabel: 'settings_remove_ads',
  );
  final FocusNode _manageFocus = FocusNode(
    debugLabel: 'settings_manage_accounts',
  );
  final FocusNode _deviceInfoFocus = FocusNode(
    debugLabel: 'settings_device_info',
  );
  bool _removeAdsFocused = false;
  bool _manageFocused = false;
  bool _deviceInfoFocused = false;

  @override
  void dispose() {
    _removeAdsFocus.dispose();
    _manageFocus.dispose();
    _deviceInfoFocus.dispose();
    super.dispose();
  }

  Future<void> _openDeviceInfo() async {
    await showDeviceInfoDialog(context, returnFocus: _deviceInfoFocus);
  }

  Future<void> _openRemoveAdsDialog() async {
    await showRemoveAdsActivateDialog(context, returnFocus: _removeAdsFocus);
  }

  Widget _iconActionButton({
    required FocusNode focusNode,
    required bool focused,
    required ValueChanged<bool> onFocusChange,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required double tvOrder,
  }) {
    final tv = isTv(context);
    final showFocus = settingsShowFocusDecor(context, focused);

    Widget btn = Focus(
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
      child: Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            // Opaque fill so focus glow never washes out the icon.
            color: const Color(0xFF1A1B22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kColorPrimary.withValues(alpha: showFocus ? 0.22 : 0.16),
                const Color(0xFF1A1B22),
              ],
            ),
            border: Border.all(
              color:
                  showFocus
                      ? kColorPrimary
                      : kColorPrimary.withValues(alpha: 0.38),
              width: showFocus ? 2 : 1,
            ),
            boxShadow:
                showFocus
                    ? [
                      BoxShadow(
                        color: kColorPrimary.withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, 0),
                      ),
                    ]
                    : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: onTap,
              child: Icon(
                icon,
                // White when focused so it stays visible over the theme glow.
                color: showFocus ? Colors.white : kColorPrimary,
                size: 16,
              ),
            ),
          ),
        ),
      ),
    );

    if (tv) {
      btn = FocusTraversalOrder(
        order: NumericFocusOrder(tvOrder),
        child: btn,
      );
    }
    return btn;
  }

  Widget _buildProfileAvatar() {
    final account = SavedAccountsRepository.getActiveAccount();
    Widget? image;
    if (account != null) {
      final file = account.avatarFile?.trim() ?? '';
      if (file.isNotEmpty && File(file).existsSync()) {
        image = Image.file(
          File(file),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      } else {
        final asset = account.avatarAsset?.trim() ?? '';
        if (asset.isNotEmpty && ProfileAvatars.isPreset(asset)) {
          image = Image.asset(
            ProfileAvatars.assetPath(asset),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        }
      }
    }

    if (image != null) {
      return SizedBox(
        width: 48,
        height: 48,
        child: ClipOval(child: image),
      );
    }

    final name = (account?.displayName ??
            widget.userInfo?.userInfo?.username ??
            '?')
        .trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipOval(
        child: ColoredBox(
          color: Colors.transparent,
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                color: kColorPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openManageAccounts() async {
    settingsReleaseTouchFocus(context);
    await Get.toNamed(screenManageAccounts);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.userInfo?.userInfo!.username ?? '—';
    final exp = expirationDate(widget.userInfo?.userInfo!.expDate);
    final tv = isTv(context);
    final showManageFocus = settingsShowFocusDecor(context, _manageFocused);
    final showRemoveAdsFocus =
        settingsShowFocusDecor(context, _removeAdsFocused);

    Widget removeAdsBtn = Focus(
      focusNode: _removeAdsFocus,
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        if (_removeAdsFocused != v) setState(() => _removeAdsFocused = v);
      },
      onKeyEvent:
          tv
              ? (node, event) => settingsTvActivateOnSelect(
                event,
                _openRemoveAdsDialog,
              )
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              kColorPrimary.withValues(alpha: 0.28),
              kColorPrimaryDark.withValues(alpha: 0.14),
            ],
          ),
          border: Border.all(
            color:
                showRemoveAdsFocus
                    ? kColorPrimary
                    : kColorPrimary.withValues(alpha: 0.55),
            width: showRemoveAdsFocus ? 1.6 : 1,
          ),
          boxShadow: settingsThemedFocusGlow(showRemoveAdsFocus),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _openRemoveAdsDialog,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FontAwesomeIcons.crown, color: kColorPrimary, size: 11),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: tv ? 160 : 128),
                    child: Text(
                      'remove_ads_activate_btn'.tr,
                      style: Get.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right,
                    color: kColorPrimary.withValues(alpha: 0.9),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Widget manageBtn = Focus(
      focusNode: _manageFocus,
      onFocusChange: (v) {
        if (!tv) {
          if (v) settingsReleaseTouchFocus(context);
          return;
        }
        if (_manageFocused != v) setState(() => _manageFocused = v);
      },
      onKeyEvent:
          tv
              ? (node, event) => settingsTvActivateOnSelect(
                event,
                _openManageAccounts,
              )
              : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              kColorPrimary.withValues(alpha: 0.22),
              kColorPrimaryDark.withValues(alpha: 0.12),
            ],
          ),
          border: Border.all(
            color:
                showManageFocus
                    ? kColorPrimary
                    : kColorPrimary.withValues(alpha: 0.4),
            width: showManageFocus ? 1.6 : 1,
          ),
          boxShadow: settingsThemedFocusGlow(showManageFocus),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _openManageAccounts,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FontAwesomeIcons.users, color: kColorPrimary, size: 11),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      'manage_accounts_btn'.tr,
                      style: Get.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                      maxLines: 1,
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

    if (tv) {
      removeAdsBtn = FocusTraversalOrder(
        order: const NumericFocusOrder(1.5),
        child: removeAdsBtn,
      );
      manageBtn = FocusTraversalOrder(
        order: const NumericFocusOrder(2),
        child: manageBtn,
      );
    }

    return _SettingsCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _buildProfileAvatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  username,
                  style: Get.textTheme.titleSmall!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      FontAwesomeIcons.calendarCheck,
                      color: kColorPrimary,
                      size: 10,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        exp,
                        style: Get.textTheme.labelSmall!.copyWith(
                          color: kColorPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          removeAdsBtn,
          if (!tv) ...[
            const SizedBox(width: 6),
            manageBtn,
          ],
          const SizedBox(width: 6),
          _iconActionButton(
            focusNode: _deviceInfoFocus,
            focused: _deviceInfoFocused,
            onFocusChange: (v) {
              if (_deviceInfoFocused != v) {
                setState(() => _deviceInfoFocused = v);
              }
            },
            icon: LucideIcons.monitor_smartphone,
            tooltip: 'settings_device_info'.tr,
            onTap: _openDeviceInfo,
            tvOrder: 3,
          ),
        ],
      ),
    );
  }
}
