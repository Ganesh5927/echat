enum IdentityStatus {
  notCreated,
  created,
  verified,
  identityChanged,
  identityRevoked,
  securityError,
}

extension IdentityStatusLabel on IdentityStatus {
  String get label {
    switch (this) {
      case IdentityStatus.notCreated:
        return 'IDENTITY NOT CREATED';
      case IdentityStatus.created:
        return 'IDENTITY CREATED';
      case IdentityStatus.verified:
        return 'IDENTITY VERIFIED';
      case IdentityStatus.identityChanged:
        return 'IDENTITY CHANGED';
      case IdentityStatus.identityRevoked:
        return 'IDENTITY REVOKED';
      case IdentityStatus.securityError:
        return 'SECURITY ERROR';
    }
  }
}
