# Decentralized Job Marketplace

A blockchain-powered freelance marketplace built on the Stacks blockchain, enabling transparent contracts and secure escrow payments for freelance work.

## Overview

This project implements a decentralized freelance marketplace where clients can post jobs, freelancers can bid on projects, and payments are held in escrow until work completion. The system leverages smart contracts to ensure transparency, security, and automated payment processing.

## Features

### Core Functionality
- **Job Posting & Management**: Clients can create job postings with detailed requirements, milestones, and budgets
- **Secure Escrow System**: Automated payment holding and release based on milestone completion
- **Milestone-Based Payments**: Support for project phases with incremental payment releases
- **Transparent Contracts**: All agreements and transactions recorded on-chain
- **Dispute Resolution**: Built-in mechanisms for handling payment disputes

### Smart Contracts

#### 1. Job Contracts (`job-contracts.clar`)
Handles the core job marketplace functionality:
- Job creation and posting
- Milestone definition and tracking
- Deliverable submission and approval
- Job status management
- Freelancer application and selection

#### 2. Escrow Payments (`escrow-payments.clar`)
Manages payment security and automated releases:
- Escrow account creation and funding
- Milestone-based payment releases
- Dispute handling and resolution
- Refund mechanisms for cancelled projects
- Fee collection and distribution

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Clients     │    │   Freelancers   │    │   Arbitrators   │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   Job Marketplace DApp  │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │    Smart Contracts      │
                    │  ┌─────────────────┐   │
                    │  │ Job Contracts   │   │
                    │  └─────────────────┘   │
                    │  ┌─────────────────┐   │
                    │  │ Escrow Payments │   │
                    │  └─────────────────┘   │
                    └─────────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │    Stacks Blockchain    │
                    └─────────────────────────┘
```

## Contract Details

### Job Workflow
1. **Job Creation**: Client posts a job with requirements and budget
2. **Application Process**: Freelancers submit proposals and bids
3. **Selection**: Client selects preferred freelancer
4. **Contract Initialization**: Smart contract created with escrow funding
5. **Milestone Tracking**: Progress tracked through defined milestones
6. **Payment Release**: Funds released upon milestone completion
7. **Project Completion**: Final payment and contract closure

### Payment Security
- **Escrow Protection**: Client funds locked until work completion
- **Milestone Payments**: Gradual payment release reduces risk
- **Dispute Resolution**: Built-in arbitration for payment disputes
- **Automatic Refunds**: Failed projects trigger automatic refunds

## Getting Started

### Prerequisites
- [Clarinet](https://docs.hiro.so/clarinet) installed
- [Node.js](https://nodejs.org/) for testing
- [Stacks CLI](https://docs.stacks.co/build-with-stacks/cli) for deployment

### Installation
```bash
git clone https://github.com/ucheeze2001/decentralized-job-marketplace.git
cd decentralized-job-marketplace
npm install
```

### Testing
```bash
# Run contract tests
clarinet test

# Check contract syntax
clarinet check

# Generate test coverage
npm run test:coverage
```

### Deployment
```bash
# Deploy to testnet
clarinet deploy --network testnet

# Deploy to mainnet (production)
clarinet deploy --network mainnet
```

## Project Structure

```
decentralized-job-marketplace/
├── contracts/
│   ├── job-contracts.clar      # Job management contract
│   └── escrow-payments.clar    # Payment escrow contract
├── tests/
│   ├── job-contracts_test.ts   # Job contract tests
│   └── escrow-payments_test.ts # Escrow contract tests
├── settings/
│   ├── Devnet.toml            # Local development settings
│   ├── Testnet.toml           # Testnet configuration
│   └── Mainnet.toml           # Mainnet configuration
├── Clarinet.toml              # Main project configuration
├── package.json               # Node.js dependencies
└── README.md                  # This file
```

## Usage Examples

### Creating a Job
```clarity
;; Post a new job with milestones
(contract-call? .job-contracts create-job
  "Full-stack Web Development"
  "Build a modern e-commerce platform"
  u1000000  ;; 1000 STX budget
  (list 
    {milestone: "UI/UX Design", payment: u300000}
    {milestone: "Frontend Development", payment: u400000}
    {milestone: "Backend & Testing", payment: u300000}
  )
)
```

### Funding Escrow
```clarity
;; Fund escrow for job
(contract-call? .escrow-payments fund-escrow
  job-id
  u1000000  ;; Total payment amount
)
```

## Security Considerations

- **Access Control**: Role-based permissions for different user types
- **Input Validation**: Comprehensive validation of all user inputs
- **Overflow Protection**: Safe arithmetic operations throughout
- **State Consistency**: Atomic operations prevent inconsistent states
- **Emergency Controls**: Circuit breakers for critical functions

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Roadmap

- [ ] Advanced dispute resolution mechanisms
- [ ] Multi-currency escrow support
- [ ] Reputation system for users
- [ ] Integration with external payment processors
- [ ] Mobile application development
- [ ] Advanced analytics and reporting

## Support

For support and questions:
- Create an [Issue](https://github.com/ucheeze2001/decentralized-job-marketplace/issues)
- Join our [Discord Community](#)
- Check the [Documentation](https://docs.marketplace.example.com)

## Acknowledgments

- Built on [Stacks Blockchain](https://stacks.co/)
- Powered by [Clarity Smart Contracts](https://clarity-lang.org/)
- Testing framework: [Clarinet](https://docs.hiro.so/clarinet)