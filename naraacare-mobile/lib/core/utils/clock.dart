/// Injectable time source, so time-dependent logic is testable.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const new();

  @override
  DateTime now() => DateTime.now();
}

class FixedClock implements Clock {
  new(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration by) => current = current.add(by);
}
