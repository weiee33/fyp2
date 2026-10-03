import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MalaysiaPhone {
  static String national(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('60')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  static String? validate(String? value) =>
      RegExp(r'^1[0-9]{8,9}$').hasMatch(value ?? '')
      ? null
      : 'Enter 9–10 digits starting with 1, without +60 or the first 0.';
  static String international(String value) {
    final local = national(value);
    if (validate(local) != null)
      throw const FormatException(
        'Enter a valid Malaysian mobile number, for example 102049818.',
      );
    return '+60$local';
  }
}

class MalaysiaPhoneField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  const MalaysiaPhoneField({
    super.key,
    required this.controller,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    enabled: enabled,
    keyboardType: TextInputType.phone,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(10),
    ],
    validator: MalaysiaPhone.validate,
    decoration: const InputDecoration(
      labelText: 'Mobile number',
      hintText: '102049818',
      helperText: 'Malaysia · omit the first 0',
      prefixIcon: SizedBox(
        width: 72,
        child: Center(
          child: Text('+60', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    ),
  );
}
