part of 'main.dart';

// New / edit customer (CR-25 changes 3 and 6). The business's own GST status
// decides what the form shows:
// - not registered: no GST question, no GSTIN, no state;
// - registered: a Yes / No question with every other field already visible;
//   GSTIN and Verify only after Yes. The customer's state is saved silently
//   from the GSTIN. There is no State field.

class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({
    super.key,
    this.customer,
    this.initialName,
    this.asSheet = false,
  });

  /// Shown as a bottom sheet (phones) instead of a dialog.
  final bool asSheet;

  final Map<String, dynamic>? customer;
  final String? initialName;

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _gstinController = TextEditingController();
  final bool _businessRegistered = BusinessSettings.isGstRegistered.value;

  /// Whether the customer is GST-registered. Only asked when the business is.
  bool? _customerRegistered;
  String? _gstinStatus;
  bool _isSaving = false;
  bool _isLookingUpGstin = false;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    if (customer == null) {
      _nameController.text = widget.initialName?.trim() ?? '';
      return;
    }
    _nameController.text = customer['name']?.toString() ?? '';
    _phoneController.text = _normaliseIndianMobile(
      customer['phone']?.toString() ?? '',
    );
    _emailController.text = customer['email']?.toString() ?? '';
    _addressController.text = customer['address']?.toString() ?? '';
    _gstinController.text = customer['gstin']?.toString() ?? '';
    if (_businessRegistered) {
      _customerRegistered = _gstinController.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _gstinController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw const AuthException(
          'Your session has expired. Please sign in again.',
        );
      }
      final gstin = _gstinController.text.trim().toUpperCase();
      final customer = <String, dynamic>{
        if (!_isEditing) 'id': const Uuid().v4(),
        'user_id': user.id,
        'name': _nameController.text.trim(),
        'phone': _normaliseIndianMobile(_phoneController.text),
        'email': _emailController.text.trim().toLowerCase(),
        'address': _addressController.text.trim(),
        // A business that isn't registered never sees or changes a GSTIN;
        // one saved earlier is kept, not shown (change 6, point 3).
        if (_businessRegistered)
          'gstin': _customerRegistered == true ? gstin : ''
        else if (!_isEditing)
          'gstin': '',
        // The state comes from the GSTIN. Older customers without a GSTIN
        // keep the state they were saved with.
        if (_businessRegistered && _customerRegistered == true)
          'state': stateFromGstin(gstin)?.name
        else if (!_isEditing)
          'state': null,
      };
      late final Map<String, dynamic> saved;
      try {
        saved = Map<String, dynamic>.from(
          _isEditing
              ? await Supabase.instance.client
                    .from('customers')
                    .update(customer)
                    .eq('id', widget.customer!['id'])
                    .select()
                    .single()
              : await Supabase.instance.client
                    .from('customers')
                    .insert(customer)
                    .select()
                    .single(),
        );
      } catch (error) {
        if (error is PostgrestException || error is AuthException) rethrow;
        if (_isEditing) rethrow;
        throw const _NotSavedOffline();
      }
      if (mounted) Navigator.of(context).pop(saved);
      invoiceChanges.value++;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save customer: $e')));
    }
  }

  Future<void> _lookupCustomerGstin() async {
    final gstin = _gstinController.text.trim().toUpperCase();
    final problem = gstinError(gstin, required: true);
    if (problem != null) {
      await showGstinResult(context, problem);
      return;
    }
    setState(() => _isLookingUpGstin = true);
    try {
      final data = await _lookupGstin(gstin);
      if (!mounted) return;
      final status = gstinStatusMessage(data['status']);
      setState(() {
        _gstinController.text = data['gstin']?.toString() ?? gstin;
        final legalName = data['legal_name']?.toString().trim() ?? '';
        final tradeName = data['trade_name']?.toString().trim() ?? '';
        if (legalName.isNotEmpty || tradeName.isNotEmpty) {
          _nameController.text = _titleCase(
            tradeName.isNotEmpty ? tradeName : legalName,
          );
        }
        final address = data['address']?.toString().trim() ?? '';
        if (address.isNotEmpty) _addressController.text = _titleCase(address);
        _gstinStatus = status;
      });
      await showGstinResult(context, status);
    } catch (e) {
      if (mounted) {
        await showGstinResult(
          context,
          e is StateError ? e.message : 'GSTIN lookup failed.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLookingUpGstin = false);
    }
  }

  List<Widget> _fields() => [
    if (_businessRegistered) ...[
      const FieldLabel('Is the customer registered for GST?', required: true),
      YesNoFormField(
        initialValue: _customerRegistered,
        yesLabel: 'Yes',
        noLabel: 'No',
        onChanged: (value) => setState(() => _customerRegistered = value),
      ),
      if (_customerRegistered == true) ...[
        const SizedBox(height: 14),
        _labeledText(
          _gstinController,
          'GSTIN',
          required: true,
          hint: '15 characters',
          inputFormatters: upperCaseCodeFormatters(15),
          helper:
              _gstinStatus ??
              (_gstinState(_gstinController.text) == null
                  ? 'Tap Verify to fill the name and address.'
                  : 'State: ${_gstinState(_gstinController.text)}'),
          onChanged: (_) => setState(() => _gstinStatus = null),
          validator: (value) => gstinError(value, required: true),
          suffix: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton(
              onPressed: _isLookingUpGstin ? null : _lookupCustomerGstin,
              child: _isLookingUpGstin
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify'),
            ),
          ),
        ),
      ],
      const SizedBox(height: 14),
    ],
    _labeledText(
      _nameController,
      'Customer name',
      required: true,
      autofillHints: const [AutofillHints.name],
      inputFormatters: [_TitleCaseFormatter()],
      maxLength: 100,
      validator: (value) =>
          value.trim().isEmpty ? 'Enter the customer name' : null,
    ),
    const SizedBox(height: 14),
    _labeledText(
      _phoneController,
      'Mobile',
      optional: true,
      hint: '10 digits',
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      inputFormatters: [_IndianMobileFormatter()],
      validator: _mobileError,
    ),
    const SizedBox(height: 14),
    _labeledText(
      _emailController,
      'Email',
      optional: true,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      maxLength: 254,
      validator: (value) {
        final email = value.trim();
        return email.isEmpty ||
                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
            ? null
            : 'Enter a valid email address';
      },
    ),
    const SizedBox(height: 14),
    _labeledText(
      _addressController,
      'Address',
      optional: true,
      lines: 2,
      maxLength: 300,
      inputFormatters: [_TitleCaseFormatter()],
    ),
  ];

  @override
  Widget build(BuildContext context) => _FormDialogFrame(
    asSheet: widget.asSheet,
    title: _isEditing ? 'Edit customer' : 'New customer',
    form: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _fields(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _isSaving ? null : _saveCustomer,
        child: _isSaving
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Saving…'),
                ],
              )
            : Text(_isEditing ? 'Update customer' : 'Save customer'),
      ),
    ],
  );
}

/// A form dialog whose content scrolls inside a box at most 85% of the
/// screen tall, with the buttons fixed below a thin divider, so the last
/// field is never hidden or cut (CR-25 change 3).
class _FormDialogFrame extends StatelessWidget {
  const _FormDialogFrame({
    this.asSheet = false,
    required this.title,
    required this.form,
    required this.actions,
  });

  final bool asSheet;
  final String title;
  final Widget form;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (asSheet) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.9),
          child: _body(context),
        ),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: size.height * 0.85,
        ),
        child: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: form,
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: actions,
        ),
      ),
    ],
  );
}
