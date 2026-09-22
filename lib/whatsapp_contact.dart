String? whatsappNumber(String input) {
  var number = input.trim().replaceAll(RegExp(r'[\s()+.-]'), '');
  if (number.startsWith('00')) number = number.substring(2);
  if (number.length == 11 && number.startsWith('0')) {
    number = number.substring(1);
  }
  if (RegExp(r'^[6-9][0-9]{9}$').hasMatch(number)) number = '91$number';
  return RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(number) ? number : null;
}

Uri whatsappChatUri(String number, String message) =>
    Uri.https('wa.me', '/$number', {'text': message});
