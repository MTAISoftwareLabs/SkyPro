part of 'settings_cubit.dart';

class SettingsState {
  final bool isDemo;

  SettingsState({this.isDemo = false});

  SettingsState copyWith({
    final bool? isDemo,
  }) {
    return SettingsState(
      isDemo: isDemo ?? this.isDemo,
    );
  }
}
