<div align="center">
  <h1 align="center">Grid - Encrypted Location Sharing</h1>
  <h3>Be Hard to Track.</h3>
<div align="center">
  <img src="https://unicorn-cdn.b-cdn.net/bbdb9366-4fba-4f6f-bcb0-b6bb733736d1/-/preview/999x443/logo-grid-v2.png" alt="Logo Grid" width="50%" />
</div>
</div>
<div align="center">
  <a href="https://www.mygrid.app">mygrid.app</a>
</div>


<br/>

<div align="center">
  <a href="https://github.com/rezivure/grid-frontend/stargazers"><img alt="GitHub Repo stars" src="https://img.shields.io/github/stars/rezivure/grid-frontend"></a>
  <a href="https://x.com/rezivure"><img alt="Twitter Follow" src="https://img.shields.io/twitter/follow/rezivure"></a>
  <a href="https://github.com/rezivure/grid-frontend/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-AGPLv3-purple"></a>
</div>
<br/>

Grid is a secure, end-to-end encrypted (E2EE) location sharing application integrated with the Matrix Protocol. Built using Flutter, Grid provides a privacy-focused solution for sharing your location with trusted contacts.

## Features

- **End-to-End Encryption (E2EE)**: All location data shared through Grid is encrypted to ensure privacy and security.
- **Matrix Protocol Integration**: Grid leverages the Matrix protocol for secure communication and decentralized data storage.
- **Cross-Platform**: Developed with Flutter, Grid runs seamlessly on both Android and iOS devices.
- **Real-Time Location Sharing**: Share your real-time location with friends or groups, with fine-grained control over who can see your location.
- **Self-Hosted Capability** Grid is designed to enable users to easily self host their own backend server and map tile provider for complete control over how they share.

## Getting Started With the App
If you wish to develop/contribute PRs to application, follow the steps below:
### Prerequisites

Before you begin, ensure you have the following installed:

- **Flutter SDK**: [Install Flutter](https://flutter.dev/docs/get-started/install)
- **Android Studio**: [Download Android Studio](https://developer.android.com/studio)
- **Xcode** (for iOS development): [Install Xcode](https://developer.apple.com/xcode/)
- **CocoaPods** (for iOS): [Install CocoaPods](https://guides.cocoapods.org/using/getting-started.html)

### Installation

1. **Clone the repository**:

   ```bash
   git clone https://github.com/Rezivure/grid-frontend.git
   cd grid-frontend
   ```

2. **Install dependencies**:

   Run the following command to install the necessary dependencies:

   ```bash
   flutter pub get
   ```

3. **Set up environment variables**:

   Copy the example environment configuration and modify it with the appropriate URLs:

   ```bash
   cp .env.example .env
   ```
   Edit `.env` to configure your API and server URLs.

4. **Platform-specific setup**:

   #### For iOS:

   - Navigate to the `ios/` directory:
     
     ```bash
     cd ios
     ```

   - Install CocoaPods dependencies:

     ```bash
     pod install
     ```

   - Return to the root directory:

     ```bash
     cd ..
     ```

   #### For Android:

   No additional setup is required.

### Running the App

1. **Open Android Studio**:

    - Open the cloned repository in Android Studio.
    - Ensure your Flutter SDK is correctly set up in Android Studio.

2. **Set Up Emulator or Physical Device**:

    - Create an Android Emulator or connect a physical device.
    - Ensure the device is running and detected by Android Studio.

3. **Run the App**:

   Use the following command in the terminal to build and run the app on the connected device or emulator:

   ```bash
   flutter run
   ```

## Project Structure

- **lib/**: Contains the main Flutter application code.
- **assets/**: Stores images, icons, and other assets.
- **pubspec.yaml**: Defines the dependencies and assets for the project.
  
## Contributing

We welcome contributions! Please submit a pull request or open an issue to discuss any changes.

## License

This project is licensed under the GNU Affero General Public License v3.0 - see the [LICENSE](./LICENSE) file for details.

