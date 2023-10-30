void main() {
  final sum = CalculateRepository().calculateSum();
  if (sum > 2) {
    print('Sum is greater than 2');
  } else {
    print('Sum is less than 2');
  }
}

class CalculateRepository {
  num calculateSum() {
    return 1 + 2;
  }
}
