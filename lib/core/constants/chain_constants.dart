/// Blockchain chain constants and configurations
class ChainConstants {
  ChainConstants._();

  // EVM Chain IDs
  static const int ethereumMainnet = 1;
  static const int ethereumSepolia = 11155111;
  static const int polygonMainnet = 137;
  static const int polygonAmoy = 80002;
  static const int bnbMainnet = 56;
  static const int bnbTestnet = 97;
  static const int arbitrumOne = 42161;
  static const int arbitrumSepolia = 421614;
  static const int optimismMainnet = 10;
  static const int optimismSepolia = 11155420;
  static const int baseMainnet = 8453;
  static const int baseSepolia = 84532;
  static const int klaytnMainnet = 8217;
  static const int klaytnTestnet = 1001;

  // Solana Clusters
  static const String solanaMainnet = 'mainnet-beta';
  static const String solanaDevnet = 'devnet';
  static const String solanaTestnet = 'testnet';
}

/// Chain type enumeration
enum ChainType {
  evm,
  solana,
  sui,
}

/// Supported blockchain network
class ChainInfo {
  final int? chainId; // For EVM chains
  final String? cluster; // For non-EVM chains
  final String name;
  final String symbol;
  final String rpcUrl;
  final String? explorerUrl;
  final ChainType type;
  final bool isTestnet;
  final String? iconUrl;

  const ChainInfo({
    this.chainId,
    this.cluster,
    required this.name,
    required this.symbol,
    required this.rpcUrl,
    this.explorerUrl,
    required this.type,
    this.isTestnet = false,
    this.iconUrl,
  });

  String get identifier => chainId?.toString() ?? cluster ?? name;

  /// CAIP-2 chain identifier
  String get caip2 {
    if (type == ChainType.evm && chainId != null) {
      return 'eip155:$chainId';
    } else if (type == ChainType.solana) {
      return 'solana:$cluster';
    }
    return name;
  }
}

/// Pre-configured supported chains
class SupportedChains {
  SupportedChains._();

  static const ChainInfo ethereumMainnet = ChainInfo(
    chainId: ChainConstants.ethereumMainnet,
    name: 'Ethereum',
    symbol: 'ETH',
    rpcUrl: 'https://eth.llamarpc.com',
    explorerUrl: 'https://etherscan.io',
    type: ChainType.evm,
  );

  static const ChainInfo ethereumSepolia = ChainInfo(
    chainId: ChainConstants.ethereumSepolia,
    name: 'Ethereum Sepolia',
    symbol: 'ETH',
    rpcUrl: 'https://rpc.sepolia.org',
    explorerUrl: 'https://sepolia.etherscan.io',
    type: ChainType.evm,
    isTestnet: true,
  );

  static const ChainInfo polygonMainnet = ChainInfo(
    chainId: ChainConstants.polygonMainnet,
    name: 'Polygon',
    symbol: 'MATIC',
    rpcUrl: 'https://polygon-rpc.com',
    explorerUrl: 'https://polygonscan.com',
    type: ChainType.evm,
  );

  static const ChainInfo bnbMainnet = ChainInfo(
    chainId: ChainConstants.bnbMainnet,
    name: 'BNB Chain',
    symbol: 'BNB',
    rpcUrl: 'https://bsc-dataseed.binance.org',
    explorerUrl: 'https://bscscan.com',
    type: ChainType.evm,
  );

  static const ChainInfo arbitrumOne = ChainInfo(
    chainId: ChainConstants.arbitrumOne,
    name: 'Arbitrum One',
    symbol: 'ETH',
    rpcUrl: 'https://arb1.arbitrum.io/rpc',
    explorerUrl: 'https://arbiscan.io',
    type: ChainType.evm,
  );

  static const ChainInfo optimismMainnet = ChainInfo(
    chainId: ChainConstants.optimismMainnet,
    name: 'Optimism',
    symbol: 'ETH',
    rpcUrl: 'https://mainnet.optimism.io',
    explorerUrl: 'https://optimistic.etherscan.io',
    type: ChainType.evm,
  );

  static const ChainInfo baseMainnet = ChainInfo(
    chainId: ChainConstants.baseMainnet,
    name: 'Base',
    symbol: 'ETH',
    rpcUrl: 'https://mainnet.base.org',
    explorerUrl: 'https://basescan.org',
    type: ChainType.evm,
  );

  static const ChainInfo solanaMainnet = ChainInfo(
    cluster: ChainConstants.solanaMainnet,
    name: 'Solana',
    symbol: 'SOL',
    rpcUrl: 'https://api.mainnet-beta.solana.com',
    explorerUrl: 'https://explorer.solana.com',
    type: ChainType.solana,
  );

  static const ChainInfo solanaDevnet = ChainInfo(
    cluster: ChainConstants.solanaDevnet,
    name: 'Solana Devnet',
    symbol: 'SOL',
    rpcUrl: 'https://api.devnet.solana.com',
    explorerUrl: 'https://explorer.solana.com?cluster=devnet',
    type: ChainType.solana,
    isTestnet: true,
  );

  /// All supported EVM chains
  static const List<ChainInfo> evmChains = [
    ethereumMainnet,
    ethereumSepolia,
    polygonMainnet,
    bnbMainnet,
    arbitrumOne,
    optimismMainnet,
    baseMainnet,
  ];

  /// All supported Solana clusters
  static const List<ChainInfo> solanaChains = [
    solanaMainnet,
    solanaDevnet,
  ];

  /// All supported chains
  static List<ChainInfo> get all => [...evmChains, ...solanaChains];

  /// Get chain by ID
  static ChainInfo? getByChainId(int chainId) {
    return evmChains.where((c) => c.chainId == chainId).firstOrNull;
  }
}
