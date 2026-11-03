import 'dart:async';
import 'dart:io';

import '../data/api/api_client.dart';

/// Turns any thrown object into a short, human sentence for the UI.
String friendlyError(Object error) {
  if (error is ApiException) {
    switch (error.statusCode) {
      case 401:
        return 'Your session expired. Please sign in again.';
      case 429:
        return error.message.isNotEmpty
            ? error.message
            : 'Too many attempts. Try again in a few minutes.';
      case >= 500:
        return 'RideX is having trouble right now. Please try again.';
    }
    return error.message;
  }
  if (error is NetworkException) return error.message;
  if (error is SocketException) {
    return "You're offline. Check your connection and try again.";
  }
  if (error is TimeoutException) {
    return 'The request timed out. Check your connection and try again.';
  }
  if (error is HttpException) return 'Network error. Please try again.';
  return 'Something went wrong. Please try again.';
}

/// True when the error was caused by connectivity rather than the server.
bool isOfflineError(Object error) =>
    error is NetworkException ||
    error is SocketException ||
    error is TimeoutException;
