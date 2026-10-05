/// What a photo shows. `auto` is only a request ("detect automatically"), never a result.
enum Kind {
  plant,
  cat,
  dog,
  bird;

  static Kind? tryParse(Object? value) {
    for (final k in Kind.values) {
      if (k.name == value) return k;
    }
    return null;
  }

  bool get isAnimal => this != Kind.plant;
}

/// The category a user picks on the home screen.
enum RequestCategory {
  plant,
  cat,
  dog,
  bird,
  auto;

  Kind? get kind => Kind.tryParse(name);
}
