<?php
/**
 * Plugin Name: Apartment Admin API
 * Description: REST API endpoints for the Wild Atlantic Hub apartment admin app. Handles cleaning status, ratings, feedback, inventory management, and booking notes.
 * Version:     3.3.0
 * Author:      Wild Atlantic Apartments
 */

if (!defined('ABSPATH')) {
    exit;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. DATABASE TABLE CREATION & UPGRADES
// ─────────────────────────────────────────────────────────────────────────────

register_activation_hook(__FILE__, 'aa_create_tables');

function aa_create_tables()
{
    global $wpdb;
    $charset = $wpdb->get_charset_collate();

    // Main cleaning status table (aqu_ prefix)
    $status_table = $wpdb->prefix . 'apartment_cleaning_status';
    $sql_status = "CREATE TABLE IF NOT EXISTS $status_table (
        id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        apartment_id    VARCHAR(100) NOT NULL,
        status          VARCHAR(50)  NOT NULL DEFAULT 'not_cleaned',
        todays_rating   TINYINT      NOT NULL DEFAULT 0,
        start_time      DATETIME     DEFAULT NULL,
        end_time        DATETIME     DEFAULT NULL,
        duration_minutes INT         DEFAULT NULL,
        remarks         TEXT         DEFAULT NULL,
        cleaning_image_url VARCHAR(500) DEFAULT NULL,
        last_rated_at   DATETIME     DEFAULT NULL,
        date_created    DATE         NOT NULL,
        UNIQUE KEY apartment_date (apartment_id, date_created)
    ) $charset;";

    // Rating history table (aqu_ prefix)
    $history_table = $wpdb->prefix . 'apartment_rating_history';
    $sql_history = "CREATE TABLE IF NOT EXISTS $history_table (
        id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        apartment_id    VARCHAR(100) NOT NULL,
        rating          TINYINT      NOT NULL DEFAULT 0,
        remarks         TEXT         DEFAULT NULL,
        image_url       VARCHAR(500) DEFAULT NULL,
        rated_at        DATETIME     NOT NULL,
        date_label      VARCHAR(20)  NOT NULL
    ) $charset;";

    // Unified log table
    $log_table = 'wp_apartment_cleaning_logs';
    $sql_log = "CREATE TABLE IF NOT EXISTS $log_table (
        id                  BIGINT(20)   NOT NULL AUTO_INCREMENT,
        apartment_slug      VARCHAR(255) NOT NULL,
        status              VARCHAR(50)  NOT NULL,
        start_timestamp     DATETIME     DEFAULT NULL,
        end_timestamp       DATETIME     DEFAULT NULL,
        duration_minutes    INT(11)      DEFAULT 0,
        rating              INT(11)      DEFAULT 0,
        remarks             TEXT         DEFAULT '',
        feedback_image_url  VARCHAR(255) DEFAULT '',
        created_at          DATETIME     DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) $charset;";

    // Inventory table
    $inventory_table = $wpdb->prefix . 'apartment_inventory';
    $sql_inventory = "CREATE TABLE IF NOT EXISTS $inventory_table (
        id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        apartment_id    VARCHAR(100) NOT NULL,
        item_name       VARCHAR(255) NOT NULL,
        item_image_url  VARCHAR(500) DEFAULT NULL,
        shop_url        VARCHAR(500) DEFAULT NULL,
        quantity        INT          NOT NULL DEFAULT 0
    ) $charset;";

    // Booking Notes table
    $notes_table = $wpdb->prefix . 'apartment_booking_notes';
    $sql_notes = "CREATE TABLE IF NOT EXISTS $notes_table (
        id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        booking_key     VARCHAR(255) NOT NULL,
        note_content    LONGTEXT     DEFAULT NULL,
        updated_at      DATETIME     DEFAULT NULL,
        UNIQUE KEY booking_key (booking_key)
    ) $charset;";

    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    dbDelta($sql_status);
    dbDelta($sql_history);
    dbDelta($sql_log);
    dbDelta($sql_inventory);
    dbDelta($sql_notes);
}

// Auto-run table creation if version updates
add_action('admin_init', 'aa_check_db_version');
function aa_check_db_version()
{
    if (get_option('aa_db_version') !== '3.3.0') {
        aa_create_tables();
        update_option('aa_db_version', '3.3.0');
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. REGISTER REST API ROUTES
// ─────────────────────────────────────────────────────────────────────────────

add_action('rest_api_init', 'aa_register_routes');

function aa_register_routes()
{
    $ns = 'apartment_admin/v1';

    // Existing Routes
    register_rest_route($ns, '/status/all', [
        'methods' => 'GET',
        'callback' => 'aa_get_all_statuses',
        'permission_callback' => '__return_true',
    ]);

    register_rest_route($ns, '/status/details', [
        'methods' => 'GET',
        'callback' => 'aa_get_status_details',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/status/update', [
        'methods' => 'POST',
        'callback' => 'aa_update_status',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/ratings/update', [
        'methods' => 'POST',
        'callback' => 'aa_update_rating',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/status/feedback', [
        'methods' => 'POST',
        'callback' => 'aa_save_feedback',
        'permission_callback' => 'aa_check_auth',
    ]);

    // Inventory Management Routes
    register_rest_route($ns, '/inventory/(?P<apartment_id>[a-zA-Z0-9_%+ -]+)', [
        'methods' => 'GET',
        'callback' => 'aa_get_inventory',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/inventory/update', [
        'methods' => 'POST',
        'callback' => 'aa_update_inventory',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/inventory/add', [
        'methods' => 'POST',
        'callback' => 'aa_add_inventory_api',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/inventory/delete', [
        'methods' => 'POST',
        'callback' => 'aa_delete_inventory_api',
        'permission_callback' => 'aa_check_auth',
    ]);

    // Inventory Apartments Route (Independent list for the Inventory section)
    register_rest_route($ns, '/inventory-apartments', [
        'methods' => 'GET',
        'callback' => 'aa_get_inventory_apartments',
        'permission_callback' => 'aa_check_auth',
    ]);

    // Booking Notes Routes
    register_rest_route($ns, '/booking-notes/get', [
        'methods' => 'GET',
        'callback' => 'aa_get_booking_note',
        'permission_callback' => 'aa_check_auth',
    ]);

    register_rest_route($ns, '/booking-notes/save', [
        'methods' => 'POST',
        'callback' => 'aa_save_booking_note',
        'permission_callback' => 'aa_check_auth',
    ]);
}

function aa_check_auth(WP_REST_Request $request)
{
    return is_user_logged_in() || current_user_can('edit_posts');
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. EXISTING CORE HELPERS
// ─────────────────────────────────────────────────────────────────────────────

function aa_get_today_date($request = null) {
    if ($request instanceof WP_REST_Request) {
        $val = $request->get_param('client_date');
        if (!empty($val)) return sanitize_text_field($val);
    }
    if (!empty($_GET['client_date'])) {
        return sanitize_text_field($_GET['client_date']);
    }
    if (!empty($_REQUEST['client_date'])) {
        return sanitize_text_field($_REQUEST['client_date']);
    }
    return current_time('Y-m-d');
}

function aa_ensure_today_row(string $apartment_id, $request = null)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = aa_get_today_date($request);
    $exists = $wpdb->get_var($wpdb->prepare("SELECT id FROM $table WHERE apartment_id = %s AND date_created = %s", $apartment_id, $today));
    if (!$exists) {
        $last_status = $wpdb->get_var($wpdb->prepare("SELECT status FROM $table WHERE apartment_id = %s ORDER BY date_created DESC LIMIT 1", $apartment_id));
        $new_status = $last_status ?: 'not_cleaned';
        $wpdb->insert($table, ['apartment_id' => $apartment_id, 'status' => $new_status, 'date_created' => $today]);
    }
}

function aa_sync_to_log(string $apartment_id, $request = null)
{
    global $wpdb;
    $status_table = $wpdb->prefix . 'apartment_cleaning_status';
    $log_table = 'wp_apartment_cleaning_logs';
    $today = aa_get_today_date($request);

    $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM $status_table WHERE apartment_id = %s AND date_created = %s", $apartment_id, $today), ARRAY_A);
    if (!$row)
        return;

    $log_id = $wpdb->get_var($wpdb->prepare("SELECT id FROM $log_table WHERE apartment_slug = %s AND DATE(created_at) = %s", $apartment_id, $today));

    $log_data = [
        'apartment_slug' => $apartment_id,
        'status' => $row['status'],
        'start_timestamp' => $row['start_time'],
        'end_timestamp' => $row['end_time'],
        'duration_minutes' => (int) ($row['duration_minutes'] ?? 0),
        'rating' => (int) ($row['todays_rating'] ?? 0),
        'remarks' => $row['remarks'] ?? '',
        'feedback_image_url' => $row['cleaning_image_url'] ?? '',
    ];

    if ($log_id) {
        $wpdb->update($log_table, $log_data, ['id' => $log_id]);
    } else {
        $wpdb->insert($log_table, $log_data);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. EXISTING API CALLBACKS (STATUS & RATINGS)
// ─────────────────────────────────────────────────────────────────────────────

function aa_get_all_statuses(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = aa_get_today_date($request);
    
    // Ensure rows exist for today before returning
    $apartments = json_decode(get_option('aa_apartments', '[]'), true);
    if (!is_array($apartments)) $apartments = [];
    foreach ($apartments as $apt) {
        if (!empty($apt['id'])) {
            aa_ensure_today_row(sanitize_text_field($apt['id']), $request);
        }
    }

    $rows = $wpdb->get_results($wpdb->prepare("SELECT apartment_id, status FROM $table WHERE date_created = %s", $today), ARRAY_A);
    $result = [];
    foreach ($rows as $row) {
        $result[$row['apartment_id']] = $row['status'];
    }
    return rest_ensure_response($result);
}

function aa_get_status_details(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $history_table = $wpdb->prefix . 'apartment_rating_history';
    $today = aa_get_today_date($request);

    $apartments = json_decode(get_option('aa_apartments', '[]'), true);
    if (!is_array($apartments))
        $apartments = [];

    $details = [];

    foreach ($apartments as $apt) {
        $apt_id = sanitize_text_field($apt['id']);
        aa_ensure_today_row($apt_id, $request);

        $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM $table WHERE apartment_id = %s AND date_created = %s", $apt_id, $today), ARRAY_A);
        $history_rows = $wpdb->get_results($wpdb->prepare("SELECT todays_rating as rating, remarks, date_created as date_label, cleaning_image_url as image_url FROM $table WHERE apartment_id = %s AND date_created != %s AND todays_rating > 0 ORDER BY date_created DESC LIMIT 3", $apt_id, $today), ARRAY_A);

        // Get the most recent date this apartment was cleaned (status='cleaned' or rated)
        $last_cleaned_date = $wpdb->get_var($wpdb->prepare(
            "SELECT MAX(date_created) FROM $table WHERE apartment_id = %s AND (status = 'cleaned' OR todays_rating > 0)",
            $apt_id
        ));

        $rating_history = array_map(function ($h) {
            return ['rating' => (int) $h['rating'], 'date' => $h['date_label'], 'remarks' => $h['remarks'] ?? '', 'image_url' => $h['image_url'] ?? ''];
        }, $history_rows);

        $start_time = $row['start_time'] ? date('g:i a', strtotime($row['start_time'])) : 'N/A';
        $end_time = $row['end_time'] ? date('g:i a', strtotime($row['end_time'])) : 'N/A';
        $last_rated_at = $row['last_rated_at'] ? date('d M Y, g:i a', strtotime($row['last_rated_at'])) : 'Unknown';

        $details[] = [
            'id' => $apt_id,
            'category' => $apt['category'] ?? 'Apartment',
            'name' => $apt['name'] ?? $apt_id,
            'imageUrl' => $apt['imageUrl'] ?? '',
            'status' => $row['status'] ?? 'not_cleaned',
            'startTime' => $start_time,
            'endTime' => $end_time,
            'duration' => $row['duration_minutes'] ? $row['duration_minutes'] . ' mins' : 'N/A',
            'rating' => (int) ($row['todays_rating'] ?? 0),
            'lastRatedAt' => $last_rated_at,
            'remarks' => $row['remarks'] ?? '',
            'cleaningImageUrl' => $row['cleaning_image_url'] ?? '',
            'lastCleanedDate' => $last_cleaned_date,
            'ratingHistory' => $rating_history,
        ];
    }
    return rest_ensure_response($details);
}

function aa_update_status(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = aa_get_today_date();
    $now = current_time('mysql');

    $apartment_id = sanitize_text_field($request->get_param('apartment_id'));
    $status_to_send = sanitize_text_field($request->get_param('status'));
    $duration = (int) $request->get_param('duration_minutes');

    if (empty($apartment_id))
        return new WP_Error('missing_param', 'apartment_id is required.', ['status' => 400]);
    aa_ensure_today_row($apartment_id, $request);

    $data = [];
    switch ($status_to_send) {
        case 'start':
            $data = ['status' => 'in_progress', 'start_time' => $now, 'end_time' => null, 'duration_minutes' => $duration ?: null];
            break;
        case 'stop':
            $data = ['status' => 'cleaned', 'end_time' => $now];
            break;
        case 'reset':
            $data = ['status' => 'not_cleaned', 'start_time' => null, 'end_time' => null, 'duration_minutes' => null, 'todays_rating' => 0, 'remarks' => null, 'cleaning_image_url' => null, 'last_rated_at' => null];
            break;
        default:
            return new WP_Error('invalid_status', 'Invalid status value.', ['status' => 400]);
    }

    $wpdb->update($table, $data, ['apartment_id' => $apartment_id, 'date_created' => $today]);
    aa_sync_to_log($apartment_id, $request);
    return rest_ensure_response(['success' => true, 'message' => 'Status updated.']);
}

function aa_update_rating(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = aa_get_today_date();
    $now = current_time('mysql');

    $apartment_id = sanitize_text_field($request->get_param('apartment_id'));
    $rating = (int) $request->get_param('todays_rating');

    if (empty($apartment_id))
        return new WP_Error('missing_param', 'apartment_id is required.', ['status' => 400]);
    if ($rating < 1 || $rating > 5)
        return new WP_Error('invalid_rating', 'Rating must be between 1 and 5.', ['status' => 400]);

    aa_ensure_today_row($apartment_id, $request);
    $wpdb->update($table, ['todays_rating' => $rating, 'last_rated_at' => $now], ['apartment_id' => $apartment_id, 'date_created' => $today]);
    aa_sync_to_log($apartment_id, $request);

    return rest_ensure_response(['success' => true, 'message' => 'Rating updated.', 'last_rated_at' => date('d M Y, g:i a', strtotime($now))]);
}

function aa_save_feedback(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = aa_get_today_date();
    $now = current_time('mysql');

    $apartment_id = sanitize_text_field($request->get_param('apartment_id'));
    $remarks = sanitize_textarea_field($request->get_param('remarks'));
    $base64_image = $request->get_param('image');

    if (empty($apartment_id))
        return new WP_Error('missing_param', 'apartment_id is required.', ['status' => 400]);
    aa_ensure_today_row($apartment_id, $request);

    $image_url = null;
    if (!empty($base64_image)) {
        if (strpos($base64_image, ',') !== false)
            $base64_image = explode(',', $base64_image, 2)[1];
        $image_data = base64_decode($base64_image);
        if ($image_data === false)
            return new WP_Error('invalid_image', 'Invalid base64 image data.', ['status' => 400]);

        $finfo = new finfo(FILEINFO_MIME_TYPE);
        $mime_type = $finfo->buffer($image_data);
        $allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

        if (!in_array($mime_type, $allowed, true))
            return new WP_Error('invalid_mime', 'Only JPEG, PNG, WebP, and GIF images are allowed.', ['status' => 400]);

        $ext_map = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp', 'image/gif' => 'gif'];
        $ext = $ext_map[$mime_type];

        $filename = sanitize_file_name('cleaning_' . $apartment_id . '_' . date('Ymd_His', strtotime($now)) . '.' . $ext);
        $upload_dir = wp_upload_dir();
        $subdir = $upload_dir['basedir'] . '/cleaning-photos/' . date('Y/m', strtotime($now));
        $subdir_url = $upload_dir['baseurl'] . '/cleaning-photos/' . date('Y/m', strtotime($now));

        if (!file_exists($subdir)) {
            wp_mkdir_p($subdir);
            $htaccess = $subdir . '/../.htaccess';
            if (!file_exists($htaccess))
                file_put_contents($htaccess, "Options -Indexes\n<FilesMatch '\.(php|php3|php4|php5|phtml|pl|py|jsp|asp|htm|html|shtml|sh|cgi)$'>\n  Deny from all\n</FilesMatch>\n");
        }

        $file_path = $subdir . '/' . $filename;
        $bytes_written = file_put_contents($file_path, $image_data);
        if ($bytes_written === false)
            return new WP_Error('upload_failed', 'Failed to write image to server.', ['status' => 500]);

        $image_url = $subdir_url . '/' . $filename;
    }

    $update_data = ['remarks' => $remarks];
    if ($image_url !== null)
        $update_data['cleaning_image_url'] = $image_url;
    $wpdb->update($table, $update_data, ['apartment_id' => $apartment_id, 'date_created' => $today]);

    // Save to history
    $history_table = $wpdb->prefix . 'apartment_rating_history';
    $current_rating_row = $wpdb->get_row($wpdb->prepare("SELECT todays_rating FROM $table WHERE apartment_id = %s AND date_created = %s", $apartment_id, $today), ARRAY_A);
    $current_rating = (int) ($current_rating_row['todays_rating'] ?? 0);

    if ($current_rating > 0) {
        $exists = $wpdb->get_var($wpdb->prepare("SELECT id FROM $history_table WHERE apartment_id = %s AND date_label = %s", $apartment_id, $today));
        $history_data = ['rating' => $current_rating, 'remarks' => $remarks, 'image_url' => $image_url, 'rated_at' => $now, 'date_label' => $today];
        if ($exists) {
            $wpdb->update($history_table, $history_data, ['apartment_id' => $apartment_id, 'date_label' => $today]);
        } else {
            $wpdb->insert($history_table, array_merge(['apartment_id' => $apartment_id], $history_data));
        }
    }

    aa_sync_to_log($apartment_id);

    $response = ['success' => true, 'message' => 'Feedback saved successfully.'];
    if ($image_url)
        $response['image_url'] = $image_url;
    return rest_ensure_response($response);
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. API CALLBACKS (INVENTORY)
// ─────────────────────────────────────────────────────────────────────────────

function aa_get_inventory_apartments()
{
    $apartments = json_decode(get_option('aa_inventory_apartments', '[]'), true);
    if (!is_array($apartments)) $apartments = [];
    return rest_ensure_response($apartments);
}

function aa_get_inventory(WP_REST_Request $request)
{
    global $wpdb;
    $raw_param = $request->get_param('apartment_id');
    // rawurldecode FIRST so %20 → space, THEN sanitize (sanitize_text_field strips %XX sequences)
    $apartment_id = sanitize_text_field(rawurldecode($raw_param));
    $table = $wpdb->prefix . 'apartment_inventory';

    $results = $wpdb->get_results($wpdb->prepare("SELECT id, item_name, item_image_url, shop_url, quantity, apartment_id FROM $table WHERE apartment_id = %s", $apartment_id), ARRAY_A);

    // DEBUG: also return all distinct apartment_ids so we can see what's stored
    $all_ids = $wpdb->get_col("SELECT DISTINCT apartment_id FROM $table");

    return rest_ensure_response([
        'debug_raw_param' => $raw_param,
        'debug_decoded_id' => $apartment_id,
        'debug_all_ids_in_db' => $all_ids,
        'items' => $results ?: [],
    ]);
}

function aa_update_inventory(WP_REST_Request $request)
{
    global $wpdb;
    $id = (int) $request->get_param('id');
    $quantity = (int) $request->get_param('quantity');
    $table = $wpdb->prefix . 'apartment_inventory';

    if (!$id)
        return new WP_Error('missing_param', 'id is required.', ['status' => 400]);

    $wpdb->update($table, ['quantity' => $quantity], ['id' => $id]);
    return rest_ensure_response(['success' => true, 'message' => 'Quantity updated.']);
}

function aa_add_inventory_api(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_inventory';

    $apartment_id = sanitize_text_field($request->get_param('apartment_id'));
    $item_name = sanitize_text_field($request->get_param('item_name'));
    $item_image_url = sanitize_url($request->get_param('item_image_url'));
    $shop_url = sanitize_url($request->get_param('shop_url'));
    $quantity = (int) $request->get_param('quantity');

    if (empty($apartment_id) || empty($item_name)) {
        return new WP_Error('missing_param', 'apartment_id and item_name are required.', ['status' => 400]);
    }

    $inserted = $wpdb->insert($table, [
        'apartment_id' => $apartment_id,
        'item_name' => $item_name,
        'item_image_url' => $item_image_url,
        'shop_url' => $shop_url,
        'quantity' => $quantity
    ]);

    if ($inserted) {
        return rest_ensure_response([
            'success' => true,
            'message' => 'Inventory item added.',
            'id' => $wpdb->insert_id
        ]);
    }

    return new WP_Error('db_error', 'Could not insert inventory item.', ['status' => 500]);
}

function aa_delete_inventory_api(WP_REST_Request $request)
{
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_inventory';
    $id = (int) $request->get_param('id');

    if (empty($id)) {
        return new WP_Error('missing_param', 'id is required.', ['status' => 400]);
    }

    $deleted = $wpdb->delete($table, ['id' => $id]);

    if ($deleted) {
        return rest_ensure_response(['success' => true, 'message' => 'Inventory item deleted.']);
    }

    return new WP_Error('db_error', 'Could not delete inventory item or item not found.', ['status' => 500]);
}


// ─────────────────────────────────────────────────────────────────────────────
// 6. API CALLBACKS (BOOKING NOTES) - FIXED
// ─────────────────────────────────────────────────────────────────────────────

function aa_get_booking_note(WP_REST_Request $request)
{
    global $wpdb;
    // FIXED: Use dynamic WordPress prefix instead of hardcoded 'aqu_'
    $table = $wpdb->prefix . 'apartment_booking_notes';
    $booking_key = sanitize_text_field($request->get_param('booking_key'));

    if (empty($booking_key)) {
        return new WP_Error('missing_param', 'booking_key is required.', ['status' => 400]);
    }

    $note = $wpdb->get_var($wpdb->prepare("SELECT note_content FROM $table WHERE booking_key = %s", $booking_key));

    return rest_ensure_response([
        'booking_key' => $booking_key,
        'note' => $note ? $note : ''
    ]);
}

function aa_save_booking_note(WP_REST_Request $request)
{
    global $wpdb;
    // FIXED: Use dynamic WordPress prefix instead of hardcoded 'aqu_'
    $table = $wpdb->prefix . 'apartment_booking_notes';

    $booking_key = sanitize_text_field($request->get_param('booking_key'));
    $note_content = sanitize_textarea_field($request->get_param('note'));
    $now = current_time('mysql');

    if (empty($booking_key)) {
        return new WP_Error('missing_param', 'booking_key is required.', ['status' => 400]);
    }

    $exists = $wpdb->get_var($wpdb->prepare("SELECT id FROM $table WHERE booking_key = %s", $booking_key));

    if ($exists) {
        $wpdb->update(
            $table,
            ['note_content' => $note_content, 'updated_at' => $now],
            ['booking_key' => $booking_key]
        );
    } else {
        $wpdb->insert(
            $table,
            ['booking_key' => $booking_key, 'note_content' => $note_content, 'updated_at' => $now]
        );
    }

    return rest_ensure_response(['success' => true, 'message' => 'Note saved successfully.']);
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. ADMIN PAGE AND SCRIPTS
// ─────────────────────────────────────────────────────────────────────────────

add_action('admin_enqueue_scripts', 'aa_admin_scripts');
function aa_admin_scripts($hook)
{
    if ('settings_page_apartment-admin' !== $hook)
        return;
    wp_enqueue_media();
}

add_action('admin_menu', 'aa_admin_menu');
function aa_admin_menu()
{
    add_options_page('Apartment Admin Settings', 'Apartment Admin', 'manage_options', 'apartment-admin', 'aa_admin_page');
}

function aa_admin_page()
{
    if (!current_user_can('manage_options'))
        return;
    global $wpdb;

    // Handle POST Actions
    if (isset($_POST['aa_admin_action']) && check_admin_referer('aa_nonce')) {

        // Add/Edit Room (for Cleaning / Default)
        if ($_POST['aa_admin_action'] === 'add_room') {
            $id = sanitize_title($_POST['apt_id']);
            $name = sanitize_text_field($_POST['apt_name']);
            $cat = sanitize_text_field($_POST['apt_category']);
            $img = sanitize_url($_POST['apt_image']);

            $apts = json_decode(get_option('aa_apartments', '[]'), true);
            if (!is_array($apts)) $apts = [];
            $exists = false;
            foreach ($apts as &$a) {
                if ($a['id'] === $id) {
                    $a['name'] = $name;
                    $a['category'] = $cat;
                    $a['imageUrl'] = $img;
                    $exists = true;
                    break;
                }
            }
            if (!$exists)
                $apts[] = ['id' => $id, 'name' => $name, 'category' => $cat, 'imageUrl' => $img];
            update_option('aa_apartments', wp_json_encode($apts));
            echo '<div class="updated"><p>Saved successfully.</p></div>';
        }

        // Delete Room (for Cleaning / Default)
        if ($_POST['aa_admin_action'] === 'delete_room') {
            $id = sanitize_title($_POST['delete_apt_id']);
            $apts = json_decode(get_option('aa_apartments', '[]'), true);
            if (!is_array($apts)) $apts = [];
            $apts = array_filter($apts, function ($a) use ($id) {
                return $a['id'] !== $id;
            });
            update_option('aa_apartments', wp_json_encode(array_values($apts)));
            echo '<div class="updated"><p>Deleted successfully.</p></div>';
        }

        // Add/Edit Inventory Room
        if ($_POST['aa_admin_action'] === 'add_inv_room') {
            $id = sanitize_title($_POST['inv_apt_id']);
            $name = sanitize_text_field($_POST['inv_apt_name']);
            $cat = sanitize_text_field($_POST['inv_apt_category']);
            $img = sanitize_url($_POST['inv_apt_image']);

            $apts = json_decode(get_option('aa_inventory_apartments', '[]'), true);
            if (!is_array($apts)) $apts = [];
            $exists = false;
            foreach ($apts as &$a) {
                if ($a['id'] === $id) {
                    $a['name'] = $name;
                    $a['category'] = $cat;
                    $a['imageUrl'] = $img;
                    $exists = true;
                    break;
                }
            }
            if (!$exists)
                $apts[] = ['id' => $id, 'name' => $name, 'category' => $cat, 'imageUrl' => $img];
            update_option('aa_inventory_apartments', wp_json_encode($apts));
            echo '<div class="updated"><p>Inventory Listing saved successfully.</p></div>';
        }

        // Delete Inventory Room
        if ($_POST['aa_admin_action'] === 'delete_inv_room') {
            $id = sanitize_title($_POST['delete_inv_apt_id']);
            $apts = json_decode(get_option('aa_inventory_apartments', '[]'), true);
            if (!is_array($apts)) $apts = [];
            $apts = array_filter($apts, function ($a) use ($id) {
                return $a['id'] !== $id;
            });
            update_option('aa_inventory_apartments', wp_json_encode(array_values($apts)));
            echo '<div class="updated"><p>Inventory Listing deleted successfully.</p></div>';
        }

        // Add Inventory Item
        if ($_POST['aa_admin_action'] === 'add_inventory') {
            $wpdb->insert($wpdb->prefix . 'apartment_inventory', [
                'apartment_id' => sanitize_text_field($_POST['inv_apt_id']),
                'item_name' => sanitize_text_field($_POST['inv_name']),
                'item_image_url' => sanitize_url($_POST['inv_image']),
                'shop_url' => sanitize_url($_POST['inv_url']),
                'quantity' => (int) $_POST['inv_qty']
            ]);
            echo '<div class="updated"><p>Inventory item added.</p></div>';
        }

        // Edit/Update Inventory Item
        if ($_POST['aa_admin_action'] === 'edit_inventory') {
            $wpdb->update($wpdb->prefix . 'apartment_inventory', [
                'apartment_id' => sanitize_text_field($_POST['inv_apt_id']),
                'item_name' => sanitize_text_field($_POST['inv_name']),
                'item_image_url' => sanitize_url($_POST['inv_image']),
                'shop_url' => sanitize_url($_POST['inv_url']),
                'quantity' => (int) $_POST['inv_qty']
            ], ['id' => (int) $_POST['inv_id']]);
            echo '<div class="updated"><p>Inventory item updated successfully.</p></div>';
        }

        // Delete Inventory Item
        if ($_POST['aa_admin_action'] === 'delete_inventory') {
            $wpdb->delete($wpdb->prefix . 'apartment_inventory', ['id' => (int) $_POST['delete_inv_id']]);
            echo '<div class="updated"><p>Inventory item deleted.</p></div>';
        }

        // Bulk Delete Inventory Items
        if ($_POST['aa_admin_action'] === 'bulk_delete_inventory' && !empty($_POST['bulk_delete_ids']) && is_array($_POST['bulk_delete_ids'])) {
            $deleted_count = 0;
            foreach ($_POST['bulk_delete_ids'] as $id_to_delete) {
                $wpdb->delete($wpdb->prefix . 'apartment_inventory', ['id' => (int) $id_to_delete]);
                $deleted_count++;
            }
            echo '<div class="updated"><p>' . $deleted_count . ' inventory items deleted successfully.</p></div>';
        }

        // Save Raw JSON Fallback
        if ($_POST['aa_admin_action'] === 'save_json') {
            $raw = stripslashes($_POST['aa_apartments_json'] ?? '[]');
            if (is_array(json_decode($raw, true))) {
                update_option('aa_apartments', wp_json_encode(json_decode($raw, true)));
                echo '<div class="updated"><p>JSON saved.</p></div>';
            } else {
                echo '<div class="error"><p>Invalid JSON format.</p></div>';
            }
        }
    }

    $apartments = json_decode(get_option('aa_apartments', '[]'), true) ?: [];
    $inventory_apartments = json_decode(get_option('aa_inventory_apartments', '[]'), true) ?: [];
    ?>
    <style>
        .aa-tabs {
            margin-top: 20px;
        }

        .aa-tab-content {
            display: none;
            background: #fff;
            padding: 20px;
            border: 1px solid #ccd0d4;
            margin-top: -1px;
        }

        .aa-tab-content.active {
            display: block;
        }

        .aa-table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }

        .aa-table th,
        .aa-table td {
            padding: 10px;
            border: 1px solid #ddd;
            text-align: left;
        }

        .aa-table th {
            background: #f9f9f9;
        }

        .aa-thumbnail {
            max-width: 60px;
            height: auto;
            border-radius: 4px;
        }
    </style>

    <div class="wrap">
        <h1>Apartment Admin Settings</h1>

        <h2 class="nav-tab-wrapper aa-tabs">
            <a href="#tab-rooms" class="nav-tab nav-tab-active">Cleaning Listings</a>
            <a href="#tab-inventory-rooms" class="nav-tab">Inventory Listings</a>
            <a href="#tab-inventory" class="nav-tab">Inventory Items</a>
            <a href="#tab-json" class="nav-tab">Advanced (JSON)</a>
            <a href="#tab-diagnostics" class="nav-tab">Diagnostics</a>
        </h2>

        <div id="tab-rooms" class="aa-tab-content active">
            <h3>Manage Cleaning Listings</h3>
            <table class="aa-table">
                <tr>
                    <th>Image</th>
                    <th>ID</th>
                    <th>Category</th>
                    <th>Name</th>
                    <th>Actions</th>
                </tr>
                <?php foreach ($apartments as $apt): ?>
                    <tr>
                        <td><?php if (!empty($apt['imageUrl']))
                            echo '<img src="' . esc_url($apt['imageUrl']) . '" class="aa-thumbnail">'; ?>
                        </td>
                        <td><?php echo esc_html($apt['id']); ?></td>
                        <td><?php echo esc_html($apt['category'] ?? 'Apartment'); ?></td>
                        <td><?php echo esc_html($apt['name']); ?></td>
                        <td>
                            <form method="post" style="display:inline;">
                                <?php wp_nonce_field('aa_nonce'); ?>
                                <input type="hidden" name="aa_admin_action" value="delete_room">
                                <input type="hidden" name="delete_apt_id" value="<?php echo esc_attr($apt['id']); ?>">
                                <button type="submit" class="button"
                                    onclick="return confirm('Delete this room?');">Delete</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </table>

            <hr>
            <h3>Add / Update Cleaning Listing</h3>
            <form method="post">
                <?php wp_nonce_field('aa_nonce'); ?>
                <input type="hidden" name="aa_admin_action" value="add_room">
                <table class="form-table">
                    <tr>
                        <th><label>Category</label></th>
                        <td><select name="apt_category">
                                <option value="Apartment">Apartment</option>
                                <option value="Room">Room</option>
                            </select></td>
                    </tr>
                    <tr>
                        <th><label>Unique ID (Slug)</label></th>
                        <td><input type="text" name="apt_id" required class="regular-text"
                                placeholder="e.g. apt_1 or room_102"> <small>Use this to edit an existing one too.</small>
                        </td>
                    </tr>
                    <tr>
                        <th><label>Name</label></th>
                        <td><input type="text" name="apt_name" required class="regular-text"
                                placeholder="e.g. 9 Eyre Square"></td>
                    </tr>
                    <tr>
                        <th><label>Image URL</label></th>
                        <td>
                            <input type="text" name="apt_image" class="regular-text image-url-input">
                            <button class="button upload-image-btn">Select Image</button>
                        </td>
                    </tr>
                </table>
                <p><button type="submit" class="button button-primary">Save Location</button></p>
            </form>
        </div>

        <div id="tab-inventory-rooms" class="aa-tab-content">
            <h3>Manage Inventory Listings</h3>
            <table class="aa-table">
                <tr>
                    <th>Image</th>
                    <th>ID</th>
                    <th>Category</th>
                    <th>Name</th>
                    <th>Actions</th>
                </tr>
                <?php foreach ($inventory_apartments as $apt): ?>
                    <tr>
                        <td><?php if (!empty($apt['imageUrl']))
                            echo '<img src="' . esc_url($apt['imageUrl']) . '" class="aa-thumbnail">'; ?>
                        </td>
                        <td><?php echo esc_html($apt['id']); ?></td>
                        <td><?php echo esc_html($apt['category'] ?? 'Apartment'); ?></td>
                        <td><?php echo esc_html($apt['name']); ?></td>
                        <td>
                            <form method="post" style="display:inline;">
                                <?php wp_nonce_field('aa_nonce'); ?>
                                <input type="hidden" name="aa_admin_action" value="delete_inv_room">
                                <input type="hidden" name="delete_inv_apt_id" value="<?php echo esc_attr($apt['id']); ?>">
                                <button type="submit" class="button"
                                    onclick="return confirm('Delete this inventory listing?');">Delete</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </table>

            <hr>
            <h3>Add / Update Inventory Listing</h3>
            <form method="post">
                <?php wp_nonce_field('aa_nonce'); ?>
                <input type="hidden" name="aa_admin_action" value="add_inv_room">
                <table class="form-table">
                    <tr>
                        <th><label>Category</label></th>
                        <td><select name="inv_apt_category">
                                <option value="Apartment">Apartment</option>
                                <option value="Room">Room</option>
                            </select></td>
                    </tr>
                    <tr>
                        <th><label>Unique ID (Slug)</label></th>
                        <td><input type="text" name="inv_apt_id" required class="regular-text"
                                placeholder="e.g. inv_1 or inv_102"> <small>This links to the inventory items.</small>
                        </td>
                    </tr>
                    <tr>
                        <th><label>Name</label></th>
                        <td><input type="text" name="inv_apt_name" required class="regular-text"
                                placeholder="e.g. Storage Unit A"></td>
                    </tr>
                    <tr>
                        <th><label>Image URL</label></th>
                        <td>
                            <input type="text" name="inv_apt_image" class="regular-text image-url-input">
                            <button class="button upload-image-btn">Select Image</button>
                        </td>
                    </tr>
                </table>
                <p><button type="submit" class="button button-primary">Save Inventory Listing</button></p>
            </form>
        </div>

        <div id="tab-inventory" class="aa-tab-content">
            <h3>Current Inventory</h3>

            <div
                style="margin-bottom: 15px; background: #f0f0f1; padding: 10px; border: 1px solid #ccd0d4; display: inline-block; border-radius: 4px;">
                <label for="inv-filter-apt" style="font-weight: bold; margin-right: 10px;">Filter by Property:</label>
                <select id="inv-filter-apt">
                    <option value="all">-- All Properties --</option>
                    <?php foreach ($inventory_apartments as $apt): ?>
                        <option value="<?php echo esc_attr($apt['id']); ?>"><?php echo esc_html($apt['name']); ?>
                            (<?php echo esc_html($apt['category'] ?? 'Apartment'); ?>)</option>
                    <?php endforeach; ?>
                </select>
            </div>

            <?php
            $inv_table = $wpdb->prefix . 'apartment_inventory';
            $items = $wpdb->get_results("SELECT * FROM $inv_table ORDER BY apartment_id", ARRAY_A);
            ?>
            <form method="post" id="bulk-delete-form">
                <?php wp_nonce_field('aa_nonce'); ?>
                <input type="hidden" name="aa_admin_action" value="bulk_delete_inventory">
                <div style="margin-bottom: 10px;">
                    <button type="submit" class="button" onclick="return confirm('Are you sure you want to delete the selected items?');">Delete Selected</button>
                </div>
                <table class="aa-table">
                    <tr>
                        <th style="width: 30px;"><input type="checkbox" id="inv-select-all"></th>
                        <th>Image</th>
                        <th>Item Name</th>
                        <th>Room / Apartment</th>
                        <th>Shop Link</th>
                        <th>Qty</th>
                        <th>Actions</th>
                    </tr>
                <?php foreach ($items as $item): ?>
                    <tr class="inv-row" data-apt="<?php echo esc_attr($item['apartment_id']); ?>">
                        <td><input type="checkbox" name="bulk_delete_ids[]" value="<?php echo esc_attr($item['id']); ?>" class="inv-bulk-checkbox"></td>
                        <td><?php if (!empty($item['item_image_url']))
                            echo '<img src="' . esc_url($item['item_image_url']) . '" class="aa-thumbnail">'; ?>
                        </td>
                        <td><?php echo esc_html($item['item_name']); ?></td>
                        <td>
                            <?php
                            $matched_apt = array_filter($inventory_apartments, function ($a) use ($item) {
                                return $a['id'] === $item['apartment_id'];
                            });
                            $matched_apt = reset($matched_apt);
                            echo $matched_apt ? esc_html($matched_apt['name']) : esc_html($item['apartment_id']);
                            ?>
                        </td>
                        <td><?php if (!empty($item['shop_url']))
                            echo '<a href="' . esc_url($item['shop_url']) . '" target="_blank">View Shop</a>'; ?>
                        </td>
                        <td><?php echo (int) $item['quantity']; ?></td>
                        <td>
                            <button type="button" class="button button-small edit-inv-btn"
                                data-id="<?php echo esc_attr($item['id']); ?>"
                                data-apt="<?php echo esc_attr($item['apartment_id']); ?>"
                                data-name="<?php echo esc_attr($item['item_name']); ?>"
                                data-img="<?php echo esc_url($item['item_image_url']); ?>"
                                data-url="<?php echo esc_url($item['shop_url']); ?>"
                                data-qty="<?php echo esc_attr($item['quantity']); ?>">Edit</button>

                            <form method="post" style="display:inline;">
                                <?php wp_nonce_field('aa_nonce'); ?>
                                <input type="hidden" name="aa_admin_action" value="delete_inventory">
                                <input type="hidden" name="delete_inv_id" value="<?php echo esc_attr($item['id']); ?>">
                                <button type="submit" class="button button-small"
                                    onclick="return confirm('Delete this item?');">Delete</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
                <?php if (empty($items))
                    echo '<tr id="inv-no-items"><td colspan="7">No inventory items found.</td></tr>'; ?>
            </table>
            </form>

            <hr>
            <h3 id="inv-form-title">Add New Inventory Item</h3>
            <form method="post" id="inv-form">
                <?php wp_nonce_field('aa_nonce'); ?>
                <input type="hidden" name="aa_admin_action" id="form_inv_action" value="add_inventory">
                <input type="hidden" name="inv_id" id="form_inv_id" value="">

                <table class="form-table">
                    <tr>
                        <th><label>Assign To</label></th>
                        <td>
                            <select name="inv_apt_id" required>
                                <option value="">-- Select Room/Apartment --</option>
                                <?php foreach ($inventory_apartments as $apt): ?>
                                    <option value="<?php echo esc_attr($apt['id']); ?>"><?php echo esc_html($apt['name']); ?>
                                        (<?php echo esc_html($apt['category'] ?? 'Apartment'); ?>)</option>
                                <?php endforeach; ?>
                            </select>
                        </td>
                    </tr>
                    <tr>
                        <th><label>Item Name</label></th>
                        <td><input type="text" name="inv_name" required class="regular-text"
                                placeholder="e.g. Toilet Paper"></td>
                    </tr>
                    <tr>
                        <th><label>Image URL</label></th>
                        <td>
                            <input type="text" name="inv_image" class="regular-text image-url-input">
                            <button type="button" class="button upload-image-btn">Select Image</button>
                        </td>
                    </tr>
                    <tr>
                        <th><label>Shop URL</label></th>
                        <td><input type="url" name="inv_url" class="regular-text" placeholder="https://amazon.co.uk/...">
                        </td>
                    </tr>
                    <tr>
                        <th><label>Quantity</label></th>
                        <td><input type="number" name="inv_qty" value="0" min="0" class="small-text"></td>
                    </tr>
                </table>
                <p>
                    <button type="submit" class="button button-primary" id="inv-submit-btn">Add Inventory Item</button>
                    <button type="button" class="button" id="cancel-edit-btn"
                        style="display:none; margin-left: 10px;">Cancel Edit</button>
                </p>
            </form>
        </div>

        <div id="tab-json" class="aa-tab-content">
            <h3>Raw JSON (Advanced)</h3>
            <p>If you need to bulk edit locations, you can still do so here. Ensure the JSON format is perfect.</p>
            <form method="post">
                <?php wp_nonce_field('aa_nonce'); ?>
                <input type="hidden" name="aa_admin_action" value="save_json">
                <textarea name="aa_apartments_json" rows="15"
                    style="width:100%;font-family:monospace;"><?php echo esc_textarea(json_encode($apartments, JSON_PRETTY_PRINT)); ?></textarea>
                <br><br>
                <input type="submit" class="button button-primary" value="Force Save JSON">
            </form>
        </div>

        <div id="tab-diagnostics" class="aa-tab-content">
            <h3>System Health</h3>
            <?php
            $tables = [
                $wpdb->prefix . 'apartment_cleaning_status',
                $wpdb->prefix . 'apartment_inventory',
                $wpdb->prefix . 'apartment_booking_notes',
                'wp_apartment_cleaning_logs'
            ];
            foreach ($tables as $tbl) {
                $exists = $wpdb->get_var("SHOW TABLES LIKE '$tbl'") === $tbl;
                echo $exists ? "<p style='color:green;'>✅ Table <code>$tbl</code> exists.</p>" : "<p style='color:red;'>❌ Table <code>$tbl</code> NOT found.</p>";
            }

            if (isset($_GET['aa_force_tables'])) {
                aa_create_tables();
                echo '<p style="color:green;">✅ Tables verified.</p>';
            } else {
                echo '<p><a href="' . admin_url('options-general.php?page=apartment-admin&aa_force_tables=1') . '" class="button">Force Re-Create Tables</a></p>';
            }

            $upload_dir = wp_upload_dir();
            echo is_writable($upload_dir['basedir']) ? '<p style="color:green;">✅ Uploads directory writable.</p>' : '<p style="color:red;">❌ Uploads directory NOT writable: <code>' . esc_html($upload_dir['basedir']) . '</code></p>';
            ?>
        </div>
    </div>

    <script>
        jQuery(document).ready(function ($) {

            // ── Tab Switcher (scoped to .aa-tabs to avoid WP admin conflicts) ──
            $('.aa-tabs .nav-tab').on('click', function (e) {
                e.preventDefault();
                $('.aa-tabs .nav-tab').removeClass('nav-tab-active');
                $(this).addClass('nav-tab-active');
                $('.aa-tab-content').removeClass('active');
                $($(this).attr('href')).addClass('active');
            });

            // ── WP Media Uploader ──
            $('.upload-image-btn').on('click', function (e) {
                e.preventDefault();
                var targetInput = $(this).siblings('.image-url-input');
                var mediaUploader = wp.media({
                    title: 'Choose Image',
                    button: { text: 'Select' },
                    multiple: false
                });
                mediaUploader.on('select', function () {
                    var attachment = mediaUploader.state().get('selection').first().toJSON();
                    targetInput.val(attachment.url);
                });
                mediaUploader.open();
            });

            // ── Inventory Property Filter ──
            $('#inv-filter-apt').on('change', function () {
                var selectedApt = $(this).val();
                if (selectedApt === 'all') {
                    $('.inv-row').show();
                } else {
                    $('.inv-row').hide();
                    $('.inv-row[data-apt="' + selectedApt + '"]').show();
                }
            });

            // ── Edit Inventory Button ──
            $('.edit-inv-btn').on('click', function (e) {
                e.preventDefault();
                var btn = $(this);
                $('#form_inv_action').val('edit_inventory');
                $('#form_inv_id').val(btn.data('id'));
                $('select[name="inv_apt_id"]').val(btn.data('apt'));
                $('input[name="inv_name"]').val(btn.data('name'));
                $('input[name="inv_image"]').val(btn.data('img'));
                $('input[name="inv_url"]').val(btn.data('url'));
                $('input[name="inv_qty"]').val(btn.data('qty'));
                $('#inv-form-title').text('Edit Inventory Item');
                $('#inv-submit-btn').text('Update Inventory Item');
                $('#cancel-edit-btn').show();
                $('html, body').animate({ scrollTop: $('#inv-form-title').offset().top - 50 }, 500);
            });

            // ── Cancel Edit ──
            $('#cancel-edit-btn').on('click', function (e) {
                e.preventDefault();
                $('#form_inv_action').val('add_inventory');
                $('#form_inv_id').val('');
                $('select[name="inv_apt_id"]').val('');
                $('input[name="inv_name"]').val('');
                $('input[name="inv_image"]').val('');
                $('input[name="inv_url"]').val('');
                $('input[name="inv_qty"]').val('0');
                $('#inv-form-title').text('Add New Inventory Item');
                $('#inv-submit-btn').text('Add Inventory Item');
                $(this).hide();
            });

            // ── Bulk Select Logic ──
            $('#inv-select-all').on('change', function() {
                $('.inv-bulk-checkbox').prop('checked', $(this).is(':checked'));
            });

            $('.inv-bulk-checkbox').on('change', function() {
                var total = $('.inv-bulk-checkbox').length;
                var checked = $('.inv-bulk-checkbox:checked').length;
                $('#inv-select-all').prop('checked', total === checked);
            });

        });
    </script>
    <?php
}