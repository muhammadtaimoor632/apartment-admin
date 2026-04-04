<?php
/**
 * Plugin Name: Apartment Admin API
 * Description: REST API endpoints for the Wild Atlantic Hub apartment admin app.
 *              Handles cleaning status, ratings, feedback (remarks + image upload),
 *              and inventory management.
 * Version:     2.0.0
 * Author:      Wild Atlantic Apartments
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. DATABASE TABLE CREATION ON ACTIVATION
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

    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    dbDelta( $sql_status );
    dbDelta( $sql_history );
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. REGISTER REST API ROUTES
// ─────────────────────────────────────────────────────────────────────────────

add_action( 'rest_api_init', 'aa_register_routes' );

function aa_register_routes() {
    $ns = 'apartment_admin/v1';

    // GET  /status/all       – returns all apartment statuses (today)
    register_rest_route( $ns, '/status/all', [
        'methods'             => 'GET',
        'callback'            => 'aa_get_all_statuses',
        'permission_callback' => '__return_true',
    ] );

    // GET  /status/details   – returns full details including rating history
    register_rest_route( $ns, '/status/details', [
        'methods'             => 'GET',
        'callback'            => 'aa_get_status_details',
        'permission_callback' => 'aa_check_auth',
    ] );

    // POST /status/update    – start / stop / reset cleaning
    register_rest_route( $ns, '/status/update', [
        'methods'             => 'POST',
        'callback'            => 'aa_update_status',
        'permission_callback' => 'aa_check_auth',
    ] );

    // POST /ratings/update   – update today's star rating
    register_rest_route( $ns, '/ratings/update', [
        'methods'             => 'POST',
        'callback'            => 'aa_update_rating',
        'permission_callback' => 'aa_check_auth',
    ] );

    // POST /status/feedback  – save remarks + optional base64 image
    register_rest_route( $ns, '/status/feedback', [
        'methods'             => 'POST',
        'callback'            => 'aa_save_feedback',
        'permission_callback' => 'aa_check_auth',
    ] );
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. AUTHENTICATION HELPER
// ─────────────────────────────────────────────────────────────────────────────

function aa_check_auth( WP_REST_Request $request ) {
    // Accepts WordPress Application Passwords (Basic Auth)
    return is_user_logged_in() || current_user_can( 'edit_posts' );
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. HELPER – ensure today's row exists for an apartment
// ─────────────────────────────────────────────────────────────────────────────

function aa_ensure_today_row( string $apartment_id ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );

    $exists = $wpdb->get_var( $wpdb->prepare(
        "SELECT id FROM $table WHERE apartment_id = %s AND date_created = %s",
        $apartment_id, $today
    ) );

    if ( ! $exists ) {
        $wpdb->insert( $table, [
            'apartment_id' => $apartment_id,
            'status'       => 'not_cleaned',
            'date_created' => $today,
        ] );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. GET ALL STATUSES  (GET /status/all)
// ─────────────────────────────────────────────────────────────────────────────

function aa_get_all_statuses() {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );

    $rows = $wpdb->get_results( $wpdb->prepare(
        "SELECT apartment_id, status FROM $table WHERE date_created = %s",
        $today
    ), ARRAY_A );

    $result = [];
    foreach ( $rows as $row ) {
        $result[ $row['apartment_id'] ] = $row['status'];
    }

    return rest_ensure_response( $result );
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. GET STATUS DETAILS  (GET /status/details)
// ─────────────────────────────────────────────────────────────────────────────

function aa_get_status_details() {
    global $wpdb;
    $table         = $wpdb->prefix . 'apartment_cleaning_status';
    $history_table = $wpdb->prefix . 'apartment_rating_history';
    $today         = current_time( 'Y-m-d' );

    // Fetch apartments from options (stored as JSON array of {id, name, imageUrl})
    $apartments = get_option( 'aa_apartments', '[]' );
    $apartments = json_decode( $apartments, true );
    if ( ! is_array( $apartments ) ) {
        $apartments = [];
    }

    $details = [];

    foreach ( $apartments as $apt ) {
        $apt_id = sanitize_text_field( $apt['id'] );

        aa_ensure_today_row( $apt_id );

        $row = $wpdb->get_row( $wpdb->prepare(
            "SELECT * FROM $table WHERE apartment_id = %s AND date_created = %s",
            $apt_id, $today
        ), ARRAY_A );

        // Rating history (last 5 entries, excluding today) - from the main cleaning status table
        $history_rows = $wpdb->get_results( $wpdb->prepare(
            "SELECT todays_rating AS rating, remarks, cleaning_image_url AS image_url, date_created AS date_label
             FROM $table
             WHERE apartment_id = %s AND date_created != %s AND (todays_rating > 0 OR remarks != '')
             ORDER BY date_created DESC
             LIMIT 5",
            $apt_id, $today
        ), ARRAY_A );

        $rating_history = array_map( function( $h ) {
            return [
                'rating'  => (int) $h['rating'],
                'date'    => date('d M Y', strtotime($h['date_label'])),
                'remarks' => current(explode('||', $h['remarks'] ?? '')) ?: $h['remarks'] ?? '',
                'image_url' => $h['image_url'] ?? '',
            ];
        }, $history_rows );

        // Format times
        $start_time = $row['start_time']
            ? date( 'g:i a', strtotime( $row['start_time'] ) )
            : 'N/A';
        $end_time = $row['end_time']
            ? date( 'g:i a', strtotime( $row['end_time'] ) )
            : 'N/A';
        $last_rated_at = $row['last_rated_at']
            ? date( 'd M Y, g:i a', strtotime( $row['last_rated_at'] ) )
            : 'Unknown';

        $details[] = [
            'id'               => $apt_id,
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

// ─────────────────────────────────────────────────────────────────────────────
// 7. UPDATE STATUS  (POST /status/update)
// ─────────────────────────────────────────────────────────────────────────────

function aa_update_status( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );
    $now   = current_time( 'mysql' );

    $apartment_id    = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $status_to_send  = sanitize_text_field( $request->get_param( 'status' ) );
    $rating          = (int) $request->get_param( 'todays_rating' );
    $duration        = (int) $request->get_param( 'duration_minutes' );

    if ( empty( $apartment_id ) ) {
        return new WP_Error( 'missing_param', 'apartment_id is required.', [ 'status' => 400 ] );
    }

    aa_ensure_today_row( $apartment_id );

    $data = [];

    switch ( $status_to_send ) {
        case 'start':
            $data = [
                'status'           => 'in_progress',
                'start_time'       => $now,
                'end_time'         => null,
                'duration_minutes' => $duration ?: null,
            ];
            break;

        case 'stop':
            $data = [
                'status'   => 'cleaned',
                'end_time' => $now,
            ];
            break;

        case 'reset':
            $data = [
                'status'           => 'not_cleaned',
                'start_time'       => null,
                'end_time'         => null,
                'duration_minutes' => null,
                'todays_rating'    => 0,
                'remarks'          => null,
                'cleaning_image_url' => null,
                'last_rated_at'    => null,
            ];
            break;

        default:
            return new WP_Error( 'invalid_status', 'Invalid status value.', [ 'status' => 400 ] );
    }

    $wpdb->update(
        $table,
        $data,
        [ 'apartment_id' => $apartment_id, 'date_created' => $today ]
    );

    return rest_ensure_response( [ 'success' => true, 'message' => 'Status updated.' ] );
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. UPDATE RATING  (POST /ratings/update)
// ─────────────────────────────────────────────────────────────────────────────

function aa_update_rating( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );
    $now   = current_time( 'mysql' );

    $apartment_id = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $rating       = (int) $request->get_param( 'todays_rating' );

    if ( empty( $apartment_id ) ) {
        return new WP_Error( 'missing_param', 'apartment_id is required.', [ 'status' => 400 ] );
    }

    if ( $rating < 1 || $rating > 5 ) {
        return new WP_Error( 'invalid_rating', 'Rating must be between 1 and 5.', [ 'status' => 400 ] );
    }

    aa_ensure_today_row( $apartment_id );

    $wpdb->update(
        $table,
        [
            'todays_rating' => $rating,
            'last_rated_at' => $now,
        ],
        [ 'apartment_id' => $apartment_id, 'date_created' => $today ]
    );

    return rest_ensure_response( [
        'success'      => true,
        'message'      => 'Rating updated.',
        'last_rated_at' => date( 'd M Y, g:i a', strtotime( $now ) ),
    ] );
}

// ─────────────────────────────────────────────────────────────────────────────
// 9. SAVE FEEDBACK – REMARKS + IMAGE UPLOAD  (POST /status/feedback)
// ─────────────────────────────────────────────────────────────────────────────

function aa_save_feedback( WP_REST_Request $request ) {
    global $wpdb;
    $table = $wpdb->prefix . 'apartment_cleaning_status';
    $today = current_time( 'Y-m-d' );
    $now   = current_time( 'mysql' );

    $apartment_id = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $remarks      = sanitize_textarea_field( $request->get_param( 'remarks' ) );
    $base64_image = $request->get_param( 'image' ); // nullable

    if ( empty( $apartment_id ) ) {
        return new WP_Error( 'missing_param', 'apartment_id is required.', [ 'status' => 400 ] );
    }

    aa_ensure_today_row( $apartment_id );

    $image_url = null;

    // ── Upload image if provided ────────────────────────────────────────────
    if ( ! empty( $base64_image ) ) {
        // Strip any data URI prefix (e.g. "data:image/jpeg;base64,")
        if ( strpos( $base64_image, ',' ) !== false ) {
            $base64_image = explode( ',', $base64_image, 2 )[1];
        }

        $image_data = base64_decode( $base64_image );
        if ( $image_data === false ) {
            return new WP_Error( 'invalid_image', 'Invalid base64 image data.', [ 'status' => 400 ] );
        }

        // Detect image type from decoded data
        $finfo     = new finfo( FILEINFO_MIME_TYPE );
        $mime_type = $finfo->buffer( $image_data );
        $allowed   = [ 'image/jpeg', 'image/png', 'image/webp', 'image/gif' ];

        if ( ! in_array( $mime_type, $allowed, true ) ) {
            return new WP_Error( 'invalid_mime', 'Only JPEG, PNG, WebP, and GIF images are allowed.', [ 'status' => 400 ] );
        }

        $ext_map = [
            'image/jpeg' => 'jpg',
            'image/png'  => 'png',
            'image/webp' => 'webp',
            'image/gif'  => 'gif',
        ];
        $ext = $ext_map[ $mime_type ];

        // Build a unique filename
        $filename = sanitize_file_name(
            'cleaning_' . $apartment_id . '_' . date( 'Ymd_His', strtotime( $now ) ) . '.' . $ext
        );

        // Use WordPress upload directory
        $upload_dir  = wp_upload_dir();
        $subdir      = $upload_dir['basedir'] . '/cleaning-photos/' . date( 'Y/m', strtotime( $now ) );
        $subdir_url  = $upload_dir['baseurl'] . '/cleaning-photos/' . date( 'Y/m', strtotime( $now ) );

        // Create directory if it doesn't exist
        if ( ! file_exists( $subdir ) ) {
            wp_mkdir_p( $subdir );

            // Protect with .htaccess (allow images only)
            $htaccess = $subdir . '/../.htaccess';
            if ( ! file_exists( $htaccess ) ) {
                file_put_contents( $htaccess,
                    "Options -Indexes\n" .
                    "<FilesMatch '\.(php|php3|php4|php5|phtml|pl|py|jsp|asp|htm|html|shtml|sh|cgi)$'>\n" .
                    "  Deny from all\n" .
                    "</FilesMatch>\n"
                );
            }
        }

        $file_path = $subdir . '/' . $filename;

        // Write file to disk
        $bytes_written = file_put_contents( $file_path, $image_data );
        if ( $bytes_written === false ) {
            return new WP_Error(
                'upload_failed',
                'Failed to write image to server. Check directory permissions on wp-content/uploads/cleaning-photos/',
                [ 'status' => 500 ]
            );
        }

        $image_url = $subdir_url . '/' . $filename;
    }

    // ── Build update data ───────────────────────────────────────────────────
    $update_data = [ 'remarks' => $remarks ];
    if ( $image_url !== null ) {
        $update_data['cleaning_image_url'] = $image_url;
    }

    $wpdb->update(
        $table,
        $update_data,
        [ 'apartment_id' => $apartment_id, 'date_created' => $today ]
    );

    // ── Also update rating history with today's remarks ─────────────────────
    $history_table = $wpdb->prefix . 'apartment_rating_history';
    $current_rating_row = $wpdb->get_row( $wpdb->prepare(
        "SELECT todays_rating FROM $table WHERE apartment_id = %s AND date_created = %s",
        $apartment_id, $today
    ), ARRAY_A );

    $current_rating = (int) ( $current_rating_row['todays_rating'] ?? 0 );

    if ( $current_rating > 0 ) {
        // Upsert today's history entry
        $exists = $wpdb->get_var( $wpdb->prepare(
            "SELECT id FROM $history_table WHERE apartment_id = %s AND date_label = %s",
            $apartment_id, $today
        ) );

        $history_data = [
            'rating'     => $current_rating,
            'remarks'    => $remarks,
            'image_url'  => $image_url,
            'rated_at'   => $now,
            'date_label' => $today,
        ];

        if ( $exists ) {
            $wpdb->update( $history_table, $history_data,
                [ 'apartment_id' => $apartment_id, 'date_label' => $today ] );
        } else {
            $wpdb->insert( $history_table,
                array_merge( [ 'apartment_id' => $apartment_id ], $history_data ) );
        }
    }

    $response = [
        'success' => true,
        'message' => 'Feedback saved successfully.',
    ];
    if ( $image_url ) {
        $response['image_url'] = $image_url;
    }

    return rest_ensure_response( $response );
}

// ─────────────────────────────────────────────────────────────────────────────
// 10. ADMIN PAGE – Manage Apartment List
// ─────────────────────────────────────────────────────────────────────────────

add_action( 'admin_menu', 'aa_admin_menu' );

function aa_admin_menu() {
    add_options_page(
        'Apartment Admin Settings',
        'Apartment Admin',
        'manage_options',
        'apartment-admin',
        'aa_admin_page'
    );
}

function aa_admin_page() {
    if ( ! current_user_can( 'manage_options' ) ) {
        return;
    }

    // Save apartments list
    if ( isset( $_POST['aa_save_apartments'] ) && check_admin_referer( 'aa_save_apartments_nonce' ) ) {
        $raw = stripslashes( $_POST['aa_apartments_json'] ?? '[]' );
        // Basic validation
        $decoded = json_decode( $raw, true );
        if ( is_array( $decoded ) ) {
            update_option( 'aa_apartments', wp_json_encode( $decoded ) );
            echo '<div class="updated"><p>Apartments saved.</p></div>';
        } else {
            echo '<div class="error"><p>Invalid JSON. Please fix the format.</p></div>';
        }
    }

    $current = get_option( 'aa_apartments', '[]' );
    // Pretty print for the textarea
    $current_pretty = json_encode( json_decode( $current, true ), JSON_PRETTY_PRINT );
    ?>
    <div class="wrap">
        <h1>Apartment Admin Settings</h1>
        <h2>Apartment List (JSON)</h2>
        <p>Each entry must have <code>id</code>, <code>name</code>, and optionally <code>imageUrl</code>.</p>
        <p><strong>Example:</strong></p>
        <pre>[
  { "id": "apt_1", "name": "9 Eyre Square", "imageUrl": "" },
  { "id": "apt_2", "name": "12 Shop Street", "imageUrl": "" }
]</pre>
        <form method="post">
            <?php wp_nonce_field( 'aa_save_apartments_nonce' ); ?>
            <textarea name="aa_apartments_json" rows="15" style="width:100%;font-family:monospace;"><?php
                echo esc_textarea( $current_pretty );
            ?></textarea>
            <br><br>
            <input type="submit" name="aa_save_apartments" class="button button-primary" value="Save Apartments">
        </form>

        <hr>
        <h2>Diagnostics</h2>
        <?php
        global $wpdb;
        $table = $wpdb->prefix . 'apartment_cleaning_status';
        $table_exists = $wpdb->get_var( "SHOW TABLES LIKE '$table'" ) === $table;
        echo $table_exists
            ? '<p style="color:green;">✅ Database table <code>' . esc_html( $table ) . '</code> exists.</p>'
            : '<p style="color:red;">❌ Table <code>' . esc_html( $table ) . '</code> NOT found. <a href="' . admin_url( 'options-general.php?page=apartment-admin&aa_create_tables=1' ) . '">Click here to create it</a>.</p>';

        // Allow manual table creation
        if ( isset( $_GET['aa_create_tables'] ) ) {
            aa_create_tables();
            echo '<p style="color:green;">✅ Tables created / updated.</p>';
        }

        $upload_dir = wp_upload_dir();
        $photos_dir = $upload_dir['basedir'] . '/cleaning-photos/';
        $writable   = is_writable( $upload_dir['basedir'] );
        echo $writable
            ? '<p style="color:green;">✅ Uploads directory is writable. Images will save to: <code>' . esc_html( $photos_dir ) . '</code></p>'
            : '<p style="color:red;">❌ Uploads directory is NOT writable: <code>' . esc_html( $upload_dir['basedir'] ) . '</code>. Please set permissions to 755.</p>';
        ?>
    </div>
    <?php
}
