import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ScraperService {
  static Future<String?> scrapeImageUrl(String productUrl) async {
    try {
      final response = await http.get(
        Uri.parse(productUrl),
        headers: {
          // Some sites block requests without a user-agent
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10)); // Add a timeout

      if (response.statusCode == 200) {
        final body = response.body;

        // Method 1: Try to find JSON-LD script for product data
        final jsonLdRegExp = RegExp(
            r'<script type="application/ld\+json">\s*([\s\S]*?)\s*</script>',
            multiLine: true);
        final matches = jsonLdRegExp.allMatches(body);

        for (final match in matches) {
          try {
            final jsonString = match.group(1)!;
            final data = json.decode(jsonString);

            dynamic image = data['image'];
            if (image != null) {
              String? imageUrl;
              if (image is String) {
                imageUrl = image;
              } else if (image is List && image.isNotEmpty) {
                dynamic firstImage = image[0];
                if (firstImage is String) {
                  imageUrl = firstImage;
                } else if (firstImage is Map && firstImage.containsKey('url')) {
                  imageUrl = firstImage['url'];
                }
              } else if (image is Map && image.containsKey('url')) {
                imageUrl = image['url'];
              }

              if (imageUrl != null && imageUrl.isNotEmpty) {
                return _resolveUrl(productUrl, imageUrl);
              }
            }
          } catch (e) {
            // JSON parsing failed, ignore and continue
          }
        }

        // Method 2: If JSON-LD fails, try Open Graph (og:image) meta tag
        final ogImageRegExp = RegExp(
            r'<meta property="og:image" content="(.*?)"',
            multiLine: true);
        final ogMatch = ogImageRegExp.firstMatch(body);
        if (ogMatch != null && ogMatch.group(1) != null) {
          final imageUrl = ogMatch.group(1)!;
          if (imageUrl.isNotEmpty) {
            return _resolveUrl(productUrl, imageUrl);
          }
        }

        return null; // No image found
      }
    } catch (e) {
      // Handles HTTP errors, timeouts, parsing errors, etc.
      return null;
    }
    return null;
  }

  /// Helper function to convert a relative URL to an absolute one.
  static String _resolveUrl(String baseUrl, String imageUrl) {
    if (imageUrl.startsWith('http')) {
      return imageUrl;
    }
    final baseUri = Uri.parse(baseUrl);
    return baseUri.resolve(imageUrl).toString();
  }
}