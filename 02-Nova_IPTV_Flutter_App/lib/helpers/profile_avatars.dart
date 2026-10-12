/// Preset profile avatars shared by Manage Accounts.
class ProfileAvatars {
  ProfileAvatars._();

  static const assetFolder = 'assets/images/avatars';

  /// Filenames under [assetFolder].
  static const List<String> presets = [
    'profil.png',
    'homme.png',
    'maman.png',
    'pere.png',
    'famille.png',
    'utilisateur.png',
    'cinema.png',
    'joueur-de-football.png',
    'citrouille-dhalloween.png',
  ];

  static String assetPath(String fileName) => '$assetFolder/$fileName';

  static bool isPreset(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return false;
    return presets.contains(n);
  }
}
