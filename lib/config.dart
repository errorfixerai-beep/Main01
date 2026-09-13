// ⚠️ EDIT THESE before running / building the app
class AppConfig {
  static const String apiBaseUrl = 'https://api.tubepilot.shop/api';   // ← backend, jaisa tha waisa hi
  static const String shareBaseUrl = 'https://play.google.com/store/apps/details?id=com.tubepilot.app'; // ← naya, sirf sharing ke liye

 // the backend can verify the token — NOT the Android/iOS client ID.
  static const String googleServerClientId =
    '348714273929-gaopmum3t87momtn46etsbiafkkopqoa.apps.googleusercontent.com';
    
  static const int diamondCostPerUpload = 10;
  static const int freeUploadsPerMonth = 20;
}