/// In-memory arguments passed between auth screens (go_router `extra`).
/// Never persisted; a restarted app starts the flow again.
class CodeArgs {
  const new({
    required this.challengeId,
    required this.email,
    this.resendAfterSeconds = 30,
  });

  final String challengeId;

  /// The user's own address, shown as plain text ("We sent a code to…").
  final String email;
  final int resendAfterSeconds;
}

/// Set New Password (A9): the reset challenge and the code entered on A8.
class NewPasswordArgs {
  const new({required this.challengeId, required this.code});

  final String challengeId;
  final String code;
}
