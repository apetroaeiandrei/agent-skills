abstract interface class PaymentGateway {
  Future<Receipt> charge(Payment payment);
}

Future<Receipt> retryPayment(Payment payment, PaymentGateway gateway) async {
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      return await gateway.charge(payment);
    } catch (error) {
      print('retry $attempt failed: $error');
    }
  }
  throw Exception('payment failed');
}

class Payment {
  const Payment({required this.id, required this.email, required this.cardNumber});

  final String id;
  final String email;
  final String cardNumber;
}

class Receipt {
  const Receipt(this.id);
  final String id;
}
