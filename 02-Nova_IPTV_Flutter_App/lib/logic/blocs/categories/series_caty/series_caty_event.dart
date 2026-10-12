part of 'series_caty_bloc.dart';

@immutable
abstract class SeriesCatyEvent {}

class GetSeriesCategories extends SeriesCatyEvent {
  final UserModel? user;
  GetSeriesCategories({this.user});
}

class ResetSeriesCatySession extends SeriesCatyEvent {}

class HydrateSeriesCategories extends SeriesCatyEvent {
  final List<CategoryModel> categories;
  HydrateSeriesCategories(this.categories);
}
