/// Wallet-specific constants and configurations
class WalletConstants {
  WalletConstants._();

  // MetaMask
  static const String metamaskDeepLink = 'metamask://';
  static const String metamaskPackageAndroid = 'io.metamask';
  static const String metamaskAppStoreId = '1438144202';

  // Trust Wallet
  static const String trustWalletDeepLink = 'trust://';
  static const String trustWalletPackageAndroid = 'com.wallet.crypto.trustapp';
  static const String trustWalletAppStoreId = '1288339409';

  // Coinbase Wallet
  static const String coinbaseDeepLink = 'cbwallet://';
  static const String coinbasePackageAndroid = 'org.toshi';
  static const String coinbaseAppStoreId = '1278383455';

  // Rainbow
  static const String rainbowDeepLink = 'rainbow://';
  static const String rainbowPackageAndroid = 'me.rainbow';
  static const String rainbowAppStoreId = '1457119021';

  // Phantom
  static const String phantomDeepLink = 'phantom://';
  static const String phantomPackageAndroid = 'app.phantom';
  static const String phantomAppStoreId = '1598432977';
  static const String phantomConnectUrl = 'https://phantom.app/ul/v1';

  // Rabby
  static const String rabbyDeepLink = 'rabby://';
  static const String rabbyPackageAndroid = 'com.debank.rabbymobile';
  static const String rabbyAppStoreId = '6474381673';
}

/// Supported wallet types
enum WalletType {
  metamask,
  walletConnect,
  coinbase,
  trustWallet,
  rainbow,
  phantom,
  rabby,
}

/// Extension for WalletType
extension WalletTypeExtension on WalletType {
  String get displayName {
    switch (this) {
      case WalletType.metamask:
        return 'MetaMask';
      case WalletType.walletConnect:
        return 'WalletConnect';
      case WalletType.coinbase:
        return 'Coinbase Wallet';
      case WalletType.trustWallet:
        return 'Trust Wallet';
      case WalletType.rainbow:
        return 'Rainbow';
      case WalletType.phantom:
        return 'Phantom';
      case WalletType.rabby:
        return 'Rabby';
    }
  }

  String get iconAsset {
    switch (this) {
      case WalletType.metamask:
        return 'assets/icons/metamask.png';
      case WalletType.walletConnect:
        return 'assets/icons/walletconnect.png';
      case WalletType.coinbase:
        return 'assets/icons/coinbase.png';
      case WalletType.trustWallet:
        return 'assets/icons/trust.png';
      case WalletType.rainbow:
        return 'assets/icons/rainbow.png';
      case WalletType.phantom:
        return 'assets/icons/phantom.png';
      case WalletType.rabby:
        return 'assets/icons/rabby.png';
    }
  }

  String get deepLinkScheme {
    switch (this) {
      case WalletType.metamask:
        return WalletConstants.metamaskDeepLink;
      case WalletType.coinbase:
        return WalletConstants.coinbaseDeepLink;
      case WalletType.trustWallet:
        return WalletConstants.trustWalletDeepLink;
      case WalletType.rainbow:
        return WalletConstants.rainbowDeepLink;
      case WalletType.phantom:
        return WalletConstants.phantomDeepLink;
      case WalletType.rabby:
        return WalletConstants.rabbyDeepLink;
      case WalletType.walletConnect:
        return '';
    }
  }

  bool get supportsEvm {
    switch (this) {
      case WalletType.metamask:
      case WalletType.walletConnect:
      case WalletType.coinbase:
      case WalletType.trustWallet:
      case WalletType.rainbow:
      case WalletType.rabby:
        return true;
      case WalletType.phantom:
        return true; // Phantom also supports Ethereum now
    }
  }

  bool get supportsSolana {
    switch (this) {
      case WalletType.phantom:
      case WalletType.coinbase:
      case WalletType.trustWallet:
        return true;
      default:
        return false;
    }
  }
}
