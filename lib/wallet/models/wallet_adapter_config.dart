import 'package:wallet_integration_practice/core/constants/app_constants.dart';

/// Configuration for wallet adapters
class WalletAdapterConfig {
  final String projectId;
  final String appName;
  final String appDescription;
  final String appUrl;
  final String appIcon;
  final List<int> supportedChainIds;
  final List<String> supportedMethods;
  final List<String> supportedEvents;

  const WalletAdapterConfig({
    required this.projectId,
    required this.appName,
    required this.appDescription,
    required this.appUrl,
    required this.appIcon,
    required this.supportedChainIds,
    required this.supportedMethods,
    required this.supportedEvents,
  });

  /// Default configuration for WalletConnect
  factory WalletAdapterConfig.defaultConfig() {
    return const WalletAdapterConfig(
      projectId: AppConstants.walletConnectProjectId,
      appName: AppConstants.appName,
      appDescription: AppConstants.appDescription,
      appUrl: AppConstants.appUrl,
      appIcon: AppConstants.appIcon,
      supportedChainIds: [1, 137, 56, 42161, 10, 8453], // Mainnet chains
      supportedMethods: [
        'eth_sendTransaction',
        'eth_signTransaction',
        'eth_sign',
        'personal_sign',
        'eth_signTypedData',
        'eth_signTypedData_v3',
        'eth_signTypedData_v4',
        'wallet_switchEthereumChain',
        'wallet_addEthereumChain',
      ],
      supportedEvents: [
        'chainChanged',
        'accountsChanged',
        'disconnect',
      ],
    );
  }

  /// Configuration for testnet
  factory WalletAdapterConfig.testnet() {
    return WalletAdapterConfig(
      projectId: AppConstants.walletConnectProjectId,
      appName: '${AppConstants.appName} (Testnet)',
      appDescription: AppConstants.appDescription,
      appUrl: AppConstants.appUrl,
      appIcon: AppConstants.appIcon,
      supportedChainIds: const [11155111, 80002, 97, 421614, 11155420, 84532],
      supportedMethods: const [
        'eth_sendTransaction',
        'eth_signTransaction',
        'eth_sign',
        'personal_sign',
        'eth_signTypedData',
        'eth_signTypedData_v3',
        'eth_signTypedData_v4',
        'wallet_switchEthereumChain',
        'wallet_addEthereumChain',
      ],
      supportedEvents: const [
        'chainChanged',
        'accountsChanged',
        'disconnect',
      ],
    );
  }
}
