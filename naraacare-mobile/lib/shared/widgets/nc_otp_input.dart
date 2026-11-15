import 'package:flutter/material.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// Six code boxes (Figma "Enter verification code"). One hidden
/// [NcTextField] does the typing, so paste and the platform's one-time-code
/// autofill work (doc 07 SEC-5.10); the boxes only display it.
class NcOtpInput extends StatefulWidget {
  const new({
    required this.controller,
    super.key,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
  });

  static const length = 6;

  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;

  @override
  State<NcOtpInput> createState() => _NcOtpInputState();
}

class _NcOtpInputState extends State<NcOtpInput> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    if (value.length == NcOtpInput.length) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final code = widget.controller.text;
    final boxes = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < NcOtpInput.length; i++)
          Container(
            width: NcSize.otpBox,
            height: NcSize.otpBox,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i == code.length && _focus.hasFocus
                  ? nc.primarySurface
                  : nc.surface,
              borderRadius: BorderRadius.circular(NcRadius.s),
              border: Border.all(
                color: widget.hasError
                    ? nc.error
                    : i < code.length
                    ? nc.primary
                    : nc.inputFill,
              ),
            ),
            child: Text(
              i < code.length ? code[i] : '',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
      ],
    );
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: Stack(
        alignment: Alignment.center,
        children: [
          boxes,
          Opacity(
            opacity: 0,
            child: NcTextField(
              controller: widget.controller,
              focusNode: _focus,
              validator: InputValidators.otp,
              maxLength: NcOtpInput.length,
              keyboardType: TextInputType.number,
              inputFormatters: [NcTextField.digitsOnly],
              autofillHints: const [AutofillHints.oneTimeCode],
              enabled: widget.enabled,
              showCursor: false,
              onChanged: _changed,
              decoration: const InputDecoration(
                border: InputBorder.none,
                filled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
