part of 'live_caty_bloc.dart';

@immutable
abstract class LiveCatyEvent {}

class GetLiveCategories extends LiveCatyEvent {
  final UserModel? user;
  GetLiveCategories({this.user});
}

class ResetLiveCatySession extends LiveCatyEvent {}

class HydrateLiveCategories extends LiveCatyEvent {
  final List<CategoryModel> categories;
  HydrateLiveCategories(this.categories);
}
