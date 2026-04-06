<?php
/**
 * Plugin Name: Apartment Admin API
 * Description: REST API endpoints for the Wild Atlantic Hub apartment admin app. Handles cleaning status, ratings, feedback, and inventory management.
 * Version:     3.1.0
 * Author:      Wild Atlantic Apartments
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. DATABASE TABLE CREATION & UPGRADES
// ─────────────────────────────────────────────────────────────────────────────

register_activation_hook( __FILE__, 'aa_create_tables' );

function aa_create_tables() {
    global $wpdb;
    $charset = $wpdb->get_charset_collate();

    // Main cleaning status table
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

    // Rating history table
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

    // NEW: Inventory table
    $inventory_table = $wpdb->prefix . 'apartment_inventory';
    $sql_inventory = "CREATE TABLE IF NOT EXISTS $inventory_table (
        id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        apartment_id    VARCHAR(100) NOT NULL,
        item_name       VARCHAR(255) NOT NULL,
        item_image_url  VARCHAR(500) DEFAULT NULL,
        shop_url        VARCHAR(500) DEFAULT NULL,
        quantity        INT          NOT NULL DEFAULT 0
    ) $charset;";

    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    dbDelta( $sql_status );
    dbDelta( $sql_history );
    dbDelta( $sql_log );
    dbDelta( $sql_inventory );
}

add_action( 'admin_init', 'aa_check_db_version' );
function aa_check_db_version() {
    if ( get_option( 'aa_db_version' ) !== '3.1.0' ) {
        aa_create_tables();
        update_option( 'aa_db_version', '3.1.0' );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. REGISTER REST API ROUTES
// ─────────────────────────────────────────────────────────────────────────────

add_action( 'rest_api_init', 'aa_register_routes' );

function aa_register_routes() {
    $ns = 'apartment_admin/v1';

    // Existing Status Routes
    register_rest_route( $ns, '/status/all', [
        'methods'             => 'GET',
        'callback'            => 'aa_get_all_statuses',
        'permission_callback' => '__return_true',
    ] );

    register_rest_route( $ns, '/status/details', [
        'methods'             => 'GET',
        'callback'            => 'aa_get_status_details',
        'permission_callback' => 'aa_check_auth',
    ] );

    register_rest_route( $ns, '/status/update', [
        'methods'             => 'POST',
        'callback'            => 'aa_update_status',
        'permission_callback' => 'aa_check_auth',
    ] );

    register_rest_route( $ns, '/ratings/update', [
        'methods'             => 'POST',
        'callback'            => 'aa_update_rating',
        'permission_callback' => 'aa_check_auth',
    ] );

    register_rest_route( $ns, '/status/feedback', [
        'methods'             => 'POST',
        'callback'            => 'aa_save_feedback',
        'permission_callback' => 'aa_check_auth',
    ] );

    // NEW Routes: Inventory Management
    register_rest_route( $ns, '/inventory/all', [
        'methods'             => 'GET',
        'callback'            => 'aa_get_all_inventory',
        'permission_callback' => 'aa_check_auth',
    ] );

    register_rest_route( $ns, '/inventory/(?P<apartment_id>[a-zA-Z0-9_-]+)', [
        'methods'             => 'GET',
        'callback'            => 'aa_get_inventory',
        'permission_callback' => 'aa_check_auth',
    ] );

    register_rest_route( $ns, '/inventory/update-stock', [
        'methods'             => 'POST',
        'callback'            => 'aa_update_inventory_stock',
        'permission_callback' => 'aa_check_auth',
    ] );

    register_rest_route( $ns, '/inventory/update-image', [
        'methods'             => 'POST',
        'callback'            => 'aa_update_inventory_image',
        'permission_callback' => 'aa_check_auth',
    ] );

    register_rest_route( $ns, '/inventory/add', [
        'methods'             => 'POST',
        'callback'            => 'aa_add_inventory_rest',
        'permission_callback' => 'aa_check_auth',
    ] );

    register_rest_route( $ns, '/inventory/delete', [
        'methods'             => 'POST',
        'callback'            => 'aa_delete_inventory_rest',
        'permission_callback' => 'aa_check_auth',
    ] );
}

function aa_check_auth( WP_REST_Request $request ) {
    return is_user_logged_in() || current_user_can( 'edit_posts' );
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. EXISTING CORE HELPERS
// ─────────────────────────────────────────────────────────────────────────────

function aa_ensure_today_row( string $apartment_id ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );
    $exists = $wpdb->get_var( $wpdb->prepare( "SELECT id FROM $table WHERE apartment_id = %s AND date_created = %s", $apartment_id, $today ) );
    if ( ! $exists ) {
        $wpdb->insert( $table, [ 'apartment_id' => $apartment_id, 'status' => 'not_cleaned', 'date_created' => $today ] );
    }
}

function aa_sync_to_log( string $apartment_id ) {
    global $wpdb;
    $status_table = $wpdb->prefix . 'apartment_cleaning_status';
    $log_table    = 'wp_apartment_cleaning_logs';
    $today        = current_time( 'Y-m-d' );

    $row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM $status_table WHERE apartment_id = %s AND date_created = %s", $apartment_id, $today ), ARRAY_A );
    if ( ! $row ) return;

    $log_id = $wpdb->get_var( $wpdb->prepare( "SELECT id FROM $log_table WHERE apartment_slug = %s AND DATE(created_at) = %s", $apartment_id, $today ) );

    $log_data = [
        'apartment_slug'     => $apartment_id,
        'status'             => $row['status'],
        'start_timestamp'    => $row['start_time'],
        'end_timestamp'      => $row['end_time'],
        'duration_minutes'   => (int) ( $row['duration_minutes'] ?? 0 ),
        'rating'             => (int) ( $row['todays_rating'] ?? 0 ),
        'remarks'            => $row['remarks'] ?? '',
        'feedback_image_url' => $row['cleaning_image_url'] ?? '',
    ];

    if ( $log_id ) {
        $wpdb->update( $log_table, $log_data, [ 'id' => $log_id ] );
    } else {
        $wpdb->insert( $log_table, $log_data );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. EXISTING API CALLBACKS (STATUS & RATINGS)
// ─────────────────────────────────────────────────────────────────────────────

function aa_get_all_statuses() {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );
    $rows = $wpdb->get_results( $wpdb->prepare( "SELECT apartment_id, status FROM $table WHERE date_created = %s", $today ), ARRAY_A );
    $result = [];
    foreach ( $rows as $row ) {
        $result[ $row['apartment_id'] ] = $row['status'];
    }
    return rest_ensure_response( $result );
}

function aa_get_status_details() {
    global $wpdb;
    $table         = $wpdb->prefix . 'apartment_cleaning_status';
    $history_table = $wpdb->prefix . 'apartment_rating_history';
    $today         = current_time( 'Y-m-d' );
    $apartments = json_decode( get_option( 'aa_apartments', '[]' ), true );
    if ( ! is_array( $apartments ) ) $apartments = [];
    $details = [];

    foreach ( $apartments as $apt ) {
        $apt_id = sanitize_text_field( $apt['id'] );
        aa_ensure_today_row( $apt_id );
        $row = $wpdb->get_row( $wpdb->prepare( "SELECT * FROM $table WHERE apartment_id = %s AND date_created = %s", $apt_id, $today ), ARRAY_A );
        $history_rows = $wpdb->get_results( $wpdb->prepare( "SELECT rating, remarks, date_label FROM $history_table WHERE apartment_id = %s AND date_label != %s ORDER BY rated_at DESC LIMIT 5", $apt_id, $today ), ARRAY_A );
        $rating_history = array_map( function( $h ) {
            return [ 'rating' => (int) $h['rating'], 'date' => $h['date_label'], 'remarks' => $h['remarks'] ?? '' ];
        }, $history_rows );
        $start_time = $row['start_time'] ? date( 'g:i a', strtotime( $row['start_time'] ) ) : 'N/A';
        $end_time = $row['end_time'] ? date( 'g:i a', strtotime( $row['end_time'] ) ) : 'N/A';
        $last_rated_at = $row['last_rated_at'] ? date( 'd M Y, g:i a', strtotime( $row['last_rated_at'] ) ) : 'Unknown';

        $details[] = [
            'id'               => $apt_id,
            'category'         => $apt['category'] ?? 'Apartment',
            'name'             => $apt['name'] ?? $apt_id,
            'imageUrl'         => $apt['imageUrl'] ?? '',
            'status'           => $row['status'] ?? 'not_cleaned',
            'startTime'        => $start_time,
            'endTime'          => $end_time,
            'duration'         => $row['duration_minutes'] ? $row['duration_minutes'] . ' mins' : 'N/A',
            'rating'           => (int) ( $row['todays_rating'] ?? 0 ),
            'lastRatedAt'      => $last_rated_at,
            'remarks'          => $row['remarks'] ?? '',
            'cleaningImageUrl' => $row['cleaning_image_url'] ?? '',
            'ratingHistory'    => $rating_history,
        ];
    }
    return rest_ensure_response( $details );
}

function aa_update_status( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );
    $now   = current_time( 'mysql' );
    $apartment_id   = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $status_to_send = sanitize_text_field( $request->get_param( 'status' ) );
    $duration       = (int) $request->get_param( 'duration_minutes' );

    if ( empty( $apartment_id ) ) return new WP_Error( 'missing_param', 'apartment_id is required.', [ 'status' => 400 ] );
    aa_ensure_today_row( $apartment_id );
    $data = [];
    switch ( $status_to_send ) {
        case 'start': $data = [ 'status' => 'in_progress', 'start_time' => $now, 'end_time' => null, 'duration_minutes' => $duration ?: null ]; break;
        case 'stop':  $data = [ 'status' => 'cleaned', 'end_time' => $now ]; break;
        case 'reset': $data = [ 'status' => 'not_cleaned', 'start_time' => null, 'end_time' => null, 'duration_minutes' => null, 'todays_rating' => 0, 'remarks' => null, 'cleaning_image_url' => null, 'last_rated_at' => null ]; break;
        default:      return new WP_Error( 'invalid_status', 'Invalid status value.', [ 'status' => 400 ] );
    }
    $wpdb->update( $table, $data, [ 'apartment_id' => $apartment_id, 'date_created' => $today ] );
    aa_sync_to_log( $apartment_id );
    return rest_ensure_response( [ 'success' => true, 'message' => 'Status updated.' ] );
}

function aa_update_rating( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );
    $now   = current_time( 'mysql' );
    $apartment_id = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $rating       = (int) $request->get_param( 'todays_rating' );

    if ( empty( $apartment_id ) ) return new WP_Error( 'missing_param', 'apartment_id is required.', [ 'status' => 400 ] );
    if ( $rating < 1 || $rating > 5 ) return new WP_Error( 'invalid_rating', 'Rating must be between 1 and 5.', [ 'status' => 400 ] );
    aa_ensure_today_row( $apartment_id );
    $wpdb->update( $table, [ 'todays_rating' => $rating, 'last_rated_at' => $now ], [ 'apartment_id' => $apartment_id, 'date_created' => $today ] );
    aa_sync_to_log( $apartment_id );
    return rest_ensure_response( [ 'success' => true, 'message' => 'Rating updated.', 'last_rated_at' => date( 'd M Y, g:i a', strtotime( $now ) ) ] );
}

function aa_save_feedback( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );
    $now   = current_time( 'mysql' );
    $apartment_id = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $remarks      = sanitize_textarea_field( $request->get_param( 'remarks' ) );
    $base64_image = $request->get_param( 'image' );

    if ( empty( $apartment_id ) ) return new WP_Error( 'missing_param', 'apartment_id is required.', [ 'status' => 400 ] );
    aa_ensure_today_row( $apartment_id );
    $image_url = null;
    if ( ! empty( $base64_image ) ) {
        if ( strpos( $base64_image, ',' ) !== false ) $base64_image = explode( ',', $base64_image, 2 )[1];
        $image_data = base64_decode( $base64_image );
        if ( $image_data === false ) return new WP_Error( 'invalid_image', 'Invalid base64 image data.', [ 'status' => 400 ] );
        $finfo = new finfo( FILEINFO_MIME_TYPE );
        $mime_type = $finfo->buffer( $image_data );
        $allowed = [ 'image/jpeg', 'image/png', 'image/webp', 'image/gif' ];
        if ( ! in_array( $mime_type, $allowed, true ) ) return new WP_Error( 'invalid_mime', 'Only JPEG, PNG, WebP, and GIF images are allowed.', [ 'status' => 400 ] );
        $ext_map = [ 'image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp', 'image/gif' => 'gif' ];
        $ext = $ext_map[ $mime_type ];
        $filename = sanitize_file_name( 'cleaning_' . $apartment_id . '_' . date( 'Ymd_His', strtotime( $now ) ) . '.' . $ext );
        $upload_dir = wp_upload_dir();
        $subdir = $upload_dir['basedir'] . '/cleaning-photos/' . date( 'Y/m', strtotime( $now ) );
        $subdir_url = $upload_dir['baseurl'] . '/cleaning-photos/' . date( 'Y/m', strtotime( $now ) );
        if ( ! file_exists( $subdir ) ) { wp_mkdir_p( $subdir ); $htaccess = $subdir . '/../.htaccess'; if ( ! file_exists( $htaccess ) ) file_put_contents( $htaccess, "Options -Indexes\n<FilesMatch '\.(php|php3|php4|php5|phtml|pl|py|jsp|asp|htm|html|shtml|sh|cgi)$'>\n  Deny from all\n</FilesMatch>\n" ); }
        $file_path = $subdir . '/' . $filename;
        $bytes_written = file_put_contents( $file_path, $image_data );
        if ( $bytes_written === false ) return new WP_Error( 'upload_failed', 'Failed to write image to server.', [ 'status' => 500 ] );
        $image_url = $subdir_url . '/' . $filename;
    }
    $update_data = [ 'remarks' => $remarks ];
    if ( $image_url !== null ) $update_data['cleaning_image_url'] = $image_url;
    $wpdb->update( $table, $update_data, [ 'apartment_id' => $apartment_id, 'date_created' => $today ] );

    // Save to history
    $history_table = $wpdb->prefix . 'apartment_rating_history';
    $current_rating_row = $wpdb->get_row( $wpdb->prepare( "SELECT todays_rating FROM $table WHERE apartment_id = %s AND date_created = %s", $apartment_id, $today ), ARRAY_A );
    $current_rating = (int) ( $current_rating_row['todays_rating'] ?? 0 );
    if ( $current_rating > 0 ) {
        $exists = $wpdb->get_var( $wpdb->prepare( "SELECT id FROM $history_table WHERE apartment_id = %s AND date_label = %s", $apartment_id, $today ) );
        $history_data = [ 'rating' => $current_rating, 'remarks' => $remarks, 'image_url' => $image_url, 'rated_at' => $now, 'date_label' => $today ];
        if ( $exists ) {
            $wpdb->update( $history_table, $history_data, [ 'apartment_id' => $apartment_id, 'date_label' => $today ] );
        } else {
            $wpdb->insert( $history_table, array_merge( [ 'apartment_id' => $apartment_id ], $history_data ) );
        }
    }
    aa_sync_to_log( $apartment_id );
    $response = [ 'success' => true, 'message' => 'Feedback saved successfully.' ];
    if ( $image_url ) $response['image_url'] = $image_url;
    return rest_ensure_response( $response );
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. NEW API CALLBACKS (INVENTORY)
// ─────────────────────────────────────────────────────────────────────────────

function aa_get_all_inventory( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_inventory';
    $results = $wpdb->get_results( "SELECT id, apartment_id, item_name, item_image_url, shop_url, quantity FROM $table", ARRAY_A );
    return rest_ensure_response( $results );
}

function aa_get_inventory( WP_REST_Request $request ) {
    global $wpdb;
    $apartment_id = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $table = $wpdb->prefix . 'apartment_inventory';
    $results = $wpdb->get_results( $wpdb->prepare( "SELECT id, apartment_id, item_name, item_image_url, shop_url, quantity FROM $table WHERE apartment_id = %s", $apartment_id ), ARRAY_A );
    return rest_ensure_response( $results );
}

function aa_update_inventory_stock( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_inventory';

    $id = (int) $request->get_param( 'item_id' );
    $action = sanitize_text_field( $request->get_param( 'action' ) );
    $apartment_id = sanitize_text_field( $request->get_param( 'apartmentId' ) ); // To return back for UI update

    if ( ! $id ) return new WP_Error( 'missing_param', 'item_id is required.', [ 'status' => 400 ] );

    $current = (int) $wpdb->get_var( $wpdb->prepare( "SELECT quantity FROM $table WHERE id = %d", $id ) );
    
    $new_stock = $current;
    if ($action === 'increment') {
        $new_stock++;
    } elseif ($action === 'decrement' && $current > 0) {
        $new_stock--;
    }

    $wpdb->update( $table, [ 'quantity' => $new_stock ], [ 'id' => $id ] );
    
    return rest_ensure_response( [ 
        'success' => true, 
        'new_stock' => $new_stock,
        'apartmentId' => $apartment_id
    ] );
}

function aa_update_inventory_image( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_inventory';
    $id = (int) $request->get_param( 'item_id' );
    $image_url = sanitize_url( $request->get_param( 'image_url' ) );
    if ( ! $id ) return new WP_Error( 'missing_param', 'item_id is required.', [ 'status' => 400 ] );
    $wpdb->update( $table, [ 'item_image_url' => $image_url ], [ 'id' => $id ] );
    return rest_ensure_response( [ 'success' => true ] );
}

function aa_add_inventory_rest( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_inventory';
    $name = sanitize_text_field( $request->get_param( 'name' ) );
    $url = sanitize_url( $request->get_param( 'url' ) );
    $apartment_id = sanitize_text_field( $request->get_param( 'apartmentId' ) );
    $stock = $request->get_param( 'stock' ); // Could be an object {"aptId": 5}
    
    $quantity = 0;
    if (is_array($stock) && isset($stock[$apartment_id])) {
        $quantity = (int)$stock[$apartment_id];
    } else {
        $quantity = (int)$stock;
    }

    $wpdb->insert( $table, [
        'apartment_id'   => $apartment_id,
        'item_name'      => $name,
        'item_image_url' => '',
        'shop_url'       => $url,
        'quantity'       => $quantity
    ] );

    $insert_id = $wpdb->insert_id;

    return rest_ensure_response([
        'id' => $insert_id,
        'apartment_id' => $apartment_id,
        'item_name' => $name,
        'shop_url' => $url,
        'item_image_url' => '',
        'quantity' => $quantity
    ]);
}

function aa_delete_inventory_rest( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_inventory';
    $id = (int) $request->get_param( 'item_id' );
    if ( ! $id ) return new WP_Error( 'missing_param', 'item_id is required.', [ 'status' => 400 ] );
    $wpdb->delete( $table, [ 'id' => $id ] );
    return rest_ensure_response( [ 'success' => true ] );
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. NEW ADMIN PAGE AND SCRIPTS
// ─────────────────────────────────────────────────────────────────────────────

add_action( 'admin_enqueue_scripts', 'aa_admin_scripts' );
function aa_admin_scripts( $hook ) {
    if ( 'settings_page_apartment-admin' !== $hook ) return;
    wp_enqueue_media();
}

add_action( 'admin_menu', 'aa_admin_menu' );
function aa_admin_menu() {
    add_options_page( 'Apartment Admin Settings', 'Apartment Admin', 'manage_options', 'apartment-admin', 'aa_admin_page' );
}

function aa_admin_page() {
    if ( ! current_user_can( 'manage_options' ) ) return;
    global $wpdb;

    if ( isset( $_POST['aa_admin_action'] ) && check_admin_referer( 'aa_nonce' ) ) {
        if ( $_POST['aa_admin_action'] === 'add_room' ) {
            $id = sanitize_title( $_POST['apt_id'] );
            $name = sanitize_text_field( $_POST['apt_name'] );
            $cat = sanitize_text_field( $_POST['apt_category'] );
            $img = sanitize_url( $_POST['apt_image'] );
            $apts = json_decode( get_option( 'aa_apartments', '[]' ), true );
            $exists = false;
            foreach ( $apts as &$a ) {
                if ( $a['id'] === $id ) { $a['name'] = $name; $a['category'] = $cat; $a['imageUrl'] = $img; $exists = true; break; }
            }
            if ( ! $exists ) $apts[] = [ 'id' => $id, 'name' => $name, 'category' => $cat, 'imageUrl' => $img ];
            update_option( 'aa_apartments', wp_json_encode( $apts ) );
            echo '<div class="updated"><p>Saved successfully.</p></div>';
        }

        if ( $_POST['aa_admin_action'] === 'delete_room' ) {
            $id = sanitize_title( $_POST['delete_apt_id'] );
            $apts = json_decode( get_option( 'aa_apartments', '[]' ), true );
            $apts = array_filter( $apts, function( $a ) use ( $id ) { return $a['id'] !== $id; } );
            update_option( 'aa_apartments', wp_json_encode( array_values( $apts ) ) );
            echo '<div class="updated"><p>Deleted successfully.</p></div>';
        }

        if ( $_POST['aa_admin_action'] === 'add_inventory' ) {
            $wpdb->insert( $wpdb->prefix . 'apartment_inventory', [
                'apartment_id'   => sanitize_text_field( $_POST['inv_apt_id'] ),
                'item_name'      => sanitize_text_field( $_POST['inv_name'] ),
                'item_image_url' => sanitize_url( $_POST['inv_image'] ),
                'shop_url'       => sanitize_url( $_POST['inv_url'] ),
                'quantity'       => (int) $_POST['inv_qty']
            ] );
            echo '<div class="updated"><p>Inventory item added.</p></div>';
        }

        if ( $_POST['aa_admin_action'] === 'delete_inventory' ) {
            $wpdb->delete( $wpdb->prefix . 'apartment_inventory', [ 'id' => (int) $_POST['delete_inv_id'] ] );
            echo '<div class="updated"><p>Inventory item deleted.</p></div>';
        }

        if ( $_POST['aa_admin_action'] === 'save_json' ) {
            $raw = stripslashes( $_POST['aa_apartments_json'] ?? '[]' );
            if ( is_array( json_decode( $raw, true ) ) ) {
                update_option( 'aa_apartments', wp_json_encode( json_decode( $raw, true ) ) );
                echo '<div class="updated"><p>JSON saved.</p></div>';
            } else {
                echo '<div class="error"><p>Invalid JSON format.</p></div>';
            }
        }
    }

    $apartments = json_decode( get_option( 'aa_apartments', '[]' ), true ) ?: [];
    ?>
    <style>
        .aa-tabs { margin-top: 20px; }
        .aa-tab-content { display: none; background: #fff; padding: 20px; border: 1px solid #ccd0d4; margin-top: -1px; }
        .aa-tab-content.active { display: block; }
        .aa-table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        .aa-table th, .aa-table td { padding: 10px; border: 1px solid #ddd; text-align: left; }
        .aa-table th { background: #f9f9f9; }
        .aa-thumbnail { max-width: 60px; height: auto; border-radius: 4px; }
    </style>

    <div class="wrap">
        <h1>Apartment Admin Settings</h1>
        
        <h2 class="nav-tab-wrapper aa-tabs">
            <a href="#tab-rooms" class="nav-tab nav-tab-active">Rooms & Apartments</a>
            <a href="#tab-inventory" class="nav-tab">Inventory List</a>
            <a href="#tab-json" class="nav-tab">Advanced (JSON)</a>
            <a href="#tab-diagnostics" class="nav-tab">Diagnostics</a>
        </h2>

        <div id="tab-rooms" class="aa-tab-content active">
            <h3>Manage Locations</h3>
            <table class="aa-table">
                <tr><th>Image</th><th>ID</th><th>Category</th><th>Name</th><th>Actions</th></tr>
                <?php foreach ( $apartments as $apt ) : ?>
                    <tr>
                        <td><?php if(!empty($apt['imageUrl'])) echo '<img src="'.esc_url($apt['imageUrl']).'" class="aa-thumbnail">'; ?></td>
                        <td><?php echo esc_html( $apt['id'] ); ?></td>
                        <td><?php echo esc_html( $apt['category'] ?? 'Apartment' ); ?></td>
                        <td><?php echo esc_html( $apt['name'] ); ?></td>
                        <td>
                            <form method="post" style="display:inline;">
                                <?php wp_nonce_field( 'aa_nonce' ); ?>
                                <input type="hidden" name="aa_admin_action" value="delete_room">
                                <input type="hidden" name="delete_apt_id" value="<?php echo esc_attr( $apt['id'] ); ?>">
                                <button type="submit" class="button" onclick="return confirm('Delete this room?');">Delete</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </table>

            <hr>
            <h3>Add / Update Location</h3>
            <form method="post">
                <?php wp_nonce_field( 'aa_nonce' ); ?>
                <input type="hidden" name="aa_admin_action" value="add_room">
                <table class="form-table">
                    <tr><th><label>Category</label></th><td><select name="apt_category"><option value="Apartment">Apartment</option><option value="Room">Room</option></select></td></tr>
                    <tr><th><label>Unique ID (Slug)</label></th><td><input type="text" name="apt_id" required class="regular-text" placeholder="e.g. apt_1 or room_102"> <small>Use this to edit an existing one too.</small></td></tr>
                    <tr><th><label>Name</label></th><td><input type="text" name="apt_name" required class="regular-text" placeholder="e.g. 9 Eyre Square"></td></tr>
                    <tr><th><label>Image URL</label></th>
                        <td>
                            <input type="text" name="apt_image" class="regular-text image-url-input">
                            <button class="button upload-image-btn">Select Image</button>
                        </td>
                    </tr>
                </table>
                <p><button type="submit" class="button button-primary">Save Location</button></p>
            </form>
        </div>

        <div id="tab-inventory" class="aa-tab-content">
            <h3>Current Inventory</h3>
            <?php 
            $inv_table = $wpdb->prefix . 'apartment_inventory';
            $items = $wpdb->get_results( "SELECT * FROM $inv_table ORDER BY apartment_id", ARRAY_A ); 
            ?>
            <table class="aa-table">
                <tr><th>Image</th><th>Item Name</th><th>Room / Apartment</th><th>Shop Link</th><th>Qty</th><th>Actions</th></tr>
                <?php foreach ( $items as $item ) : ?>
                    <tr>
                        <td><?php if(!empty($item['item_image_url'])) echo '<img src="'.esc_url($item['item_image_url']).'" class="aa-thumbnail">'; ?></td>
                        <td><?php echo esc_html( $item['item_name'] ); ?></td>
                        <td>
                            <?php 
                                $matched_apt = array_filter($apartments, function($a) use ($item) { return $a['id'] === $item['apartment_id']; });
                                $matched_apt = reset($matched_apt);
                                echo $matched_apt ? esc_html($matched_apt['name']) : esc_html($item['apartment_id']); 
                            ?>
                        </td>
                        <td><?php if(!empty($item['shop_url'])) echo '<a href="'.esc_url($item['shop_url']).'" target="_blank">View Shop</a>'; ?></td>
                        <td><?php echo (int)$item['quantity']; ?></td>
                        <td>
                            <form method="post" style="display:inline;">
                                <?php wp_nonce_field( 'aa_nonce' ); ?>
                                <input type="hidden" name="aa_admin_action" value="delete_inventory">
                                <input type="hidden" name="delete_inv_id" value="<?php echo esc_attr( $item['id'] ); ?>">
                                <button type="submit" class="button button-small" onclick="return confirm('Delete this item?');">Delete</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
                <?php if (empty($items)) echo '<tr><td colspan="6">No inventory items found.</td></tr>'; ?>
            </table>

            <hr>
            <h3>Add New Inventory Item</h3>
            <form method="post">
                <?php wp_nonce_field( 'aa_nonce' ); ?>
                <input type="hidden" name="aa_admin_action" value="add_inventory">
                <table class="form-table">
                    <tr><th><label>Assign To</label></th>
                        <td>
                            <select name="inv_apt_id" required>
                                <option value="">-- Select Room/Apartment --</option>
                                <?php foreach($apartments as $apt): ?>
                                    <option value="<?php echo esc_attr($apt['id']); ?>"><?php echo esc_html($apt['name']); ?> (<?php echo esc_html($apt['category'] ?? 'Apartment'); ?>)</option>
                                <?php endforeach; ?>
                            </select>
                        </td>
                    </tr>
                    <tr><th><label>Item Name</label></th><td><input type="text" name="inv_name" required class="regular-text" placeholder="e.g. Toilet Paper"></td></tr>
                    <tr><th><label>Image URL</label></th>
                        <td>
                            <input type="text" name="inv_image" class="regular-text image-url-input">
                            <button class="button upload-image-btn">Select Image</button>
                        </td>
                    </tr>
                    <tr><th><label>Shop URL</label></th><td><input type="url" name="inv_url" class="regular-text" placeholder="https://amazon.co.uk/..."></td></tr>
                    <tr><th><label>Quantity</label></th><td><input type="number" name="inv_qty" value="0" min="0" class="small-text"></td></tr>
                </table>
                <p><button type="submit" class="button button-primary">Add Inventory Item</button></p>
            </form>
        </div>

        <div id="tab-json" class="aa-tab-content">
            <h3>Raw JSON (Advanced)</h3>
            <p>If you need to bulk edit locations, you can still do so here. Ensure the JSON format is perfect.</p>
            <form method="post">
                <?php wp_nonce_field( 'aa_nonce' ); ?>
                <input type="hidden" name="aa_admin_action" value="save_json">
                <textarea name="aa_apartments_json" rows="15" style="width:100%;font-family:monospace;"><?php echo esc_textarea( json_encode( $apartments, JSON_PRETTY_PRINT ) ); ?></textarea>
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
                'wp_apartment_cleaning_logs'
            ];
            foreach ($tables as $tbl) {
                $exists = $wpdb->get_var( "SHOW TABLES LIKE '$tbl'" ) === $tbl;
                echo $exists ? "<p style='color:green;'>✅ Table <code>$tbl</code> exists.</p>" : "<p style='color:red;'>❌ Table <code>$tbl</code> NOT found.</p>";
            }

            if ( isset( $_GET['aa_force_tables'] ) ) {
                aa_create_tables();
                echo '<p style="color:green;">✅ Tables verified.</p>';
            } else {
                echo '<p><a href="' . admin_url( 'options-general.php?page=apartment-admin&aa_force_tables=1' ) . '" class="button">Force Re-Create Tables</a></p>';
            }

            $upload_dir = wp_upload_dir();
            echo is_writable( $upload_dir['basedir'] ) ? '<p style="color:green;">✅ Uploads directory writable.</p>' : '<p style="color:red;">❌ Uploads directory NOT writable: <code>' . esc_html( $upload_dir['basedir'] ) . '</code></p>';
            ?>
        </div>
    </div>

    <script>
    jQuery(document).ready(function($) {
        $('.nav-tab').click(function(e) {
            e.preventDefault();
            $('.nav-tab').removeClass('nav-tab-active');
            $(this).addClass('nav-tab-active');
            $('.aa-tab-content').removeClass('active');
            $($(this).attr('href')).addClass('active');
        });

        $('.upload-image-btn').click(function(e) {
            e.preventDefault();
            var targetInput = $(this).siblings('.image-url-input');
            var mediaUploader = wp.media({ title: 'Choose Image', button: { text: 'Select' }, multiple: false });
            mediaUploader.on('select', function() {
                var attachment = mediaUploader.state().get('selection').first().toJSON();
                targetInput.val(attachment.url);
            });
            mediaUploader.open();
        });
    });
    </script>
    <?php
}
