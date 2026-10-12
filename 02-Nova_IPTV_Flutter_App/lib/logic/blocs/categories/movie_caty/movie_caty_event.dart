part of 'movie_caty_bloc.dart';

@immutable
abstract class MovieCatyEvent {}

class GetMovieCategories extends MovieCatyEvent {
  final UserModel? user;
  GetMovieCategories({this.user});
}

class ResetMovieCatySession extends MovieCatyEvent {}

class HydrateMovieCategories extends MovieCatyEvent {
  final List<CategoryModel> categories;
  HydrateMovieCategories(this.categories);
}
