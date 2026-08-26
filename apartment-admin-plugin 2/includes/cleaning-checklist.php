<?php
/**
 * Cleaning Checklist endpoints + table.
 *
 * Stores the "Finish Cleaning" popup data per apartment per date.
 * Routes (namespace: apartment_admin/v1):
 *   POST /cleaning-checklist/save
 *   GET  /cleaning-checklist/get?apartment_id=...&date=YYYY-MM-DD
 *   GET  /cleaning-checklist/list?apartment_id=...   (optional history)
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

// ---------------------------------------------------------------------------
// Table creation
// ---------------------------------------------------------------------------

function aa_cleaning_checklist_table_name() {
    global $wpdb;
    return $wpdb->prefix . 'cleaning_checklists';
}

function aa_cleaning_checklist_install() {
    global $wpdb;
    $table   = aa_cleaning_checklist_table_name();
    $charset = $wpdb->get_charset_collate();

    $sql = "CREATE TABLE {$table} (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        apartment_id VARCHAR(191) NOT NULL,
        checklist_date DATE NOT NULL,
        towels_left_on_bed INT NOT NULL DEFAULT 0,
        code_set TINYINT(1) NOT NULL DEFAULT 0,
        parking_pass_checked TINYINT(1) NOT NULL DEFAULT 0,
        water_filled TINYINT(1) NOT NULL DEFAULT 0,
        submitted_at DATETIME NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY  (id),
        UNIQUE KEY apartment_date (apartment_id, checklist_date),
        KEY apartment_id (apartment_id),
        KEY checklist_date (checklist_date)
    ) {$charset};";

    require_once ABSPATH . 'wp-admin/includes/upgrade.php';
    dbDelta( $sql );
}

// Run on plugin activation. Replace __FILE__ if loaded from the main plugin file.
register_activation_hook( __FILE__, 'aa_cleaning_checklist_install' );

// Safety net: ensure the table exists even if the plugin was upgraded without
// a re-activation. Runs once and is cached.
function aa_cleaning_checklist_ensure_table() {
    if ( get_option( 'aa_cleaning_checklist_db_version' ) === '1' ) {
        return;
    }
    aa_cleaning_checklist_install();
    update_option( 'aa_cleaning_checklist_db_version', '1' );
}
add_action( 'plugins_loaded', 'aa_cleaning_checklist_ensure_table' );

// ---------------------------------------------------------------------------
// REST routes
// ---------------------------------------------------------------------------

add_action( 'rest_api_init', function () {
    register_rest_route( 'apartment_admin/v1', '/cleaning-checklist/save', [
        'methods'             => 'POST',
        'callback'            => 'aa_cleaning_checklist_save',
        'permission_callback' => function () {
            return current_user_can( 'edit_posts' );
        },
    ] );

    register_rest_route( 'apartment_admin/v1', '/cleaning-checklist/get', [
        'methods'             => 'GET',
        'callback'            => 'aa_cleaning_checklist_get',
        'permission_callback' => function () {
            return current_user_can( 'edit_posts' );
        },
    ] );

    register_rest_route( 'apartment_admin/v1', '/cleaning-checklist/list', [
        'methods'             => 'GET',
        'callback'            => 'aa_cleaning_checklist_list',
        'permission_callback' => function () {
            return current_user_can( 'edit_posts' );
        },
    ] );
} );

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

function aa_cleaning_checklist_save( WP_REST_Request $request ) {
    global $wpdb;
    $table = aa_cleaning_checklist_table_name();

    $params       = $request->get_json_params();
    $apartment_id = isset( $params['apartment_id'] ) ? sanitize_text_field( $params['apartment_id'] ) : '';
    $date         = isset( $params['date'] ) ? sanitize_text_field( $params['date'] ) : current_time( 'Y-m-d' );

    if ( empty( $apartment_id ) ) {
        return new WP_Error( 'missing_apartment_id', 'apartment_id is required', [ 'status' => 400 ] );
    }
    if ( ! preg_match( '/^\d{4}-\d{2}-\d{2}$/', $date ) ) {
        return new WP_Error( 'invalid_date', 'date must be YYYY-MM-DD', [ 'status' => 400 ] );
    }

    $towels        = isset( $params['towels_left_on_bed'] ) ? max( 0, intval( $params['towels_left_on_bed'] ) ) : 0;
    $code_set      = ! empty( $params['code_set'] ) ? 1 : 0;
    $parking_pass  = ! empty( $params['parking_pass_checked'] ) ? 1 : 0;
    $water_filled  = ! empty( $params['water_filled'] ) ? 1 : 0;
    $submitted_at  = isset( $params['submitted_at'] ) ? sanitize_text_field( $params['submitted_at'] ) : current_time( 'mysql' );

    // Convert ISO 8601 to MySQL DATETIME if needed.
    $ts = strtotime( $submitted_at );
    if ( $ts ) {
        $submitted_at = gmdate( 'Y-m-d H:i:s', $ts );
    } else {
        $submitted_at = current_time( 'mysql' );
    }

    $data = [
        'apartment_id'         => $apartment_id,
        'checklist_date'       => $date,
        'towels_left_on_bed'   => $towels,
        'code_set'             => $code_set,
        'parking_pass_checked' => $parking_pass,
        'water_filled'         => $water_filled,
        'submitted_at'         => $submitted_at,
    ];
    $formats = [ '%s', '%s', '%d', '%d', '%d', '%d', '%s' ];

    // Upsert by (apartment_id, checklist_date).
    $existing_id = $wpdb->get_var( $wpdb->prepare(
        "SELECT id FROM {$table} WHERE apartment_id = %s AND checklist_date = %s",
        $apartment_id,
        $date
    ) );

    if ( $existing_id ) {
        $result = $wpdb->update( $table, $data, [ 'id' => $existing_id ], $formats, [ '%d' ] );
        $row_id = $existing_id;
    } else {
        $result = $wpdb->insert( $table, $data, $formats );
        $row_id = $wpdb->insert_id;
    }

    if ( false === $result ) {
        return new WP_Error( 'db_error', 'Failed to save checklist: ' . $wpdb->last_error, [ 'status' => 500 ] );
    }

    return rest_ensure_response( [
        'success' => true,
        'id'      => intval( $row_id ),
        'data'    => $data,
    ] );
}

function aa_cleaning_checklist_get( WP_REST_Request $request ) {
    global $wpdb;
    $table = aa_cleaning_checklist_table_name();

    $apartment_id = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $date         = sanitize_text_field( $request->get_param( 'date' ) ?: current_time( 'Y-m-d' ) );

    if ( empty( $apartment_id ) ) {
        return new WP_Error( 'missing_apartment_id', 'apartment_id is required', [ 'status' => 400 ] );
    }

    $row = $wpdb->get_row( $wpdb->prepare(
        "SELECT * FROM {$table} WHERE apartment_id = %s AND checklist_date = %s",
        $apartment_id,
        $date
    ), ARRAY_A );

    if ( ! $row ) {
        return rest_ensure_response( [ 'found' => false ] );
    }

    return rest_ensure_response( [
        'found'                => true,
        'id'                   => intval( $row['id'] ),
        'apartment_id'         => $row['apartment_id'],
        'date'                 => $row['checklist_date'],
        'towels_left_on_bed'   => intval( $row['towels_left_on_bed'] ),
        'code_set'             => (bool) $row['code_set'],
        'parking_pass_checked' => (bool) $row['parking_pass_checked'],
        'water_filled'         => (bool) $row['water_filled'],
        'submitted_at'         => $row['submitted_at'],
    ] );
}

function aa_cleaning_checklist_list( WP_REST_Request $request ) {
    global $wpdb;
    $table = aa_cleaning_checklist_table_name();

    $apartment_id = sanitize_text_field( $request->get_param( 'apartment_id' ) );
    $limit        = max( 1, min( 100, intval( $request->get_param( 'limit' ) ?: 30 ) ) );

    if ( empty( $apartment_id ) ) {
        return new WP_Error( 'missing_apartment_id', 'apartment_id is required', [ 'status' => 400 ] );
    }

    $rows = $wpdb->get_results( $wpdb->prepare(
        "SELECT * FROM {$table} WHERE apartment_id = %s ORDER BY checklist_date DESC LIMIT %d",
        $apartment_id,
        $limit
    ), ARRAY_A );

    $out = array_map( function ( $row ) {
        return [
            'id'                   => intval( $row['id'] ),
            'apartment_id'         => $row['apartment_id'],
            'date'                 => $row['checklist_date'],
            'towels_left_on_bed'   => intval( $row['towels_left_on_bed'] ),
            'code_set'             => (bool) $row['code_set'],
            'parking_pass_checked' => (bool) $row['parking_pass_checked'],
            'water_filled'         => (bool) $row['water_filled'],
            'submitted_at'         => $row['submitted_at'],
        ];
    }, $rows ?: [] );

    return rest_ensure_response( $out );
}
