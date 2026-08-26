<?php
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

if ( ! class_exists( 'WP_List_Table' ) ) {
    require_once( ABSPATH . 'wp-admin/includes/class-wp-list-table.php' );
}

class FDP_Links_List_Table extends WP_List_Table {

    public function __construct() {
        parent::__construct( array(
            'singular' => __( 'Generated Link', 'fluent-dynamic-pages' ),
            'plural'   => __( 'Generated Links', 'fluent-dynamic-pages' ),
            'ajax'     => false
        ) );
    }

    private $submission_cache = array();

    private function get_submission_response( $submission_id ) {
        if ( isset( $this->submission_cache[ $submission_id ] ) ) {
            return $this->submission_cache[ $submission_id ];
        }
        global $wpdb;
        $response = $wpdb->get_var( $wpdb->prepare( "SELECT response FROM {$wpdb->prefix}fluentform_submissions WHERE id = %d", $submission_id ) );
        if ( $response ) {
            $this->submission_cache[ $submission_id ] = json_decode( $response, true );
        } else {
            $this->submission_cache[ $submission_id ] = array();
        }
        return $this->submission_cache[ $submission_id ];
    }

    public function get_columns() {
        return array(
            'cb'            => '<input type="checkbox" />',
            'post_id'       => __( 'Mapped Webpage', 'fluent-dynamic-pages' ),
            'form_id'       => __( 'Fluent Form', 'fluent-dynamic-pages' ),
            'submission_id' => __( 'Entry ID', 'fluent-dynamic-pages' ),
            'email'         => __( 'Email', 'fluent-dynamic-pages' ),
            'description'   => __( 'Description', 'fluent-dynamic-pages' ),
            'conditions'    => __( 'Display Conditions', 'fluent-dynamic-pages' ),
            'generated_link'=> __( 'Generated Link', 'fluent-dynamic-pages' ),
            'created_at'    => __( 'Date', 'fluent-dynamic-pages' )
        );
    }

    public function column_default( $item, $column_name ) {
        switch ( $column_name ) {
            case 'post_id':
                return '<a href="' . get_edit_post_link( $item['post_id'] ) . '">' . get_the_title( $item['post_id'] ) . '</a>';
            case 'form_id':
                global $wpdb;
                $forms_table = $wpdb->prefix . 'fluentform_forms';
                $form_title = $wpdb->get_var( $wpdb->prepare( "SELECT title FROM {$forms_table} WHERE id = %d", $item['form_id'] ) );
                return $form_title ? esc_html( $form_title ) . ' (ID: ' . $item['form_id'] . ')' : $item['form_id'];
            case 'submission_id':
                $admin_url = admin_url( 'admin.php?page=fluent_forms&route=entries&form_id=' . $item['form_id'] . '#/entries/' . $item['submission_id'] );
                return '<a href="' . esc_url( $admin_url ) . '">#' . esc_html( $item['submission_id'] ) . '</a>';
            case 'email':
            case 'description':
                $response_data = $this->get_submission_response( $item['submission_id'] );
                // Handle nested keys just in case, though usually they are direct keys
                $keys = explode('.', $column_name);
                $val = $response_data;
                foreach ($keys as $k) {
                    if (is_array($val) && isset($val[$k])) {
                        $val = $val[$k];
                    } else {
                        $val = '';
                        break;
                    }
                }
                if ( $val !== '' ) {
                    if ( is_array( $val ) ) {
                        $val = implode( ', ', $val );
                    }
                    return esc_html( $val );
                }
                return '—';
            case 'conditions':
                // Check if they have a literal field named "display_conditions" just in case
                $response_data = $this->get_submission_response( $item['submission_id'] );
                $output = array();

                if (isset($response_data['display_conditions']) && $response_data['display_conditions'] !== '') {
                    $val = $response_data['display_conditions'];
                    if (is_array($val)) {
                        $val = implode(', ', $val);
                    }
                    $output[] = esc_html($val);
                } else {
                    // Dynamically extract the fields used in the mapped page's conditions
                    $sections = get_post_meta($item['post_id'], '_fdp_dynamic_sections', true);
                    $condition_fields = array();
                    if (is_array($sections)) {
                        foreach ($sections as $section) {
                            if (isset($section['conditions']) && is_array($section['conditions'])) {
                                foreach ($section['conditions'] as $cond) {
                                    if (!empty($cond['field'])) {
                                        $condition_fields[$cond['field']] = $cond['field'];
                                    }
                                }
                            }
                        }
                    }

                    if (empty($condition_fields)) {
                        return '—';
                    }

                    foreach ($condition_fields as $field) {
                        $keys = explode('.', $field);
                        $val = $response_data;
                        foreach ($keys as $k) {
                            if (is_array($val) && isset($val[$k])) {
                                $val = $val[$k];
                            } else {
                                $val = '';
                                break;
                            }
                        }
                        if ($val !== '') {
                            if (is_array($val)) {
                                $val = implode(', ', $val);
                            }
                            $output[] = '<strong>' . esc_html($field) . ':</strong> ' . esc_html($val);
                        }
                    }
                }

                return !empty($output) ? implode('<br>', $output) : '—';
            case 'generated_link':
                $url = add_query_arg( 'fdp_hash', $item['hash'], get_permalink( $item['post_id'] ) );
                return '<a href="' . esc_url( $url ) . '" target="_blank">' . esc_url( $url ) . '</a>';
            case 'created_at':
                return $item['created_at'];
            default:
                return print_r( $item, true );
        }
    }

    public function column_cb( $item ) {
        return sprintf(
            '<input type="checkbox" name="link_id[]" value="%d" />',
            $item['id']
        );
    }

    public function get_bulk_actions() {
        return array(
            'delete' => __( 'Delete', 'fluent-dynamic-pages' )
        );
    }

    public function process_bulk_action() {
        if ( 'delete' === $this->current_action() ) {
            if ( isset( $_POST['link_id'] ) && is_array( $_POST['link_id'] ) ) {
                global $wpdb;
                $table_name = $wpdb->prefix . 'fdp_generated_links';
                $ids = array_map( 'intval', $_POST['link_id'] );
                $ids_placeholder = implode( ',', array_fill( 0, count( $ids ), '%d' ) );
                $wpdb->query( $wpdb->prepare( "DELETE FROM {$table_name} WHERE id IN ($ids_placeholder)", $ids ) );
            }
        }
    }

    public function prepare_items() {
        $this->process_bulk_action();

        global $wpdb;
        $table_name = $wpdb->prefix . 'fdp_generated_links';

        $per_page = 20;
        $current_page = $this->get_pagenum();
        
        // Ensure table exists before querying
        if ( $wpdb->get_var("SHOW TABLES LIKE '$table_name'") !== $table_name ) {
            $this->items = array();
            return;
        }

        $total_items = $wpdb->get_var( "SELECT COUNT(id) FROM {$table_name}" );

        $this->set_pagination_args( array(
            'total_items' => $total_items,
            'per_page'    => $per_page
        ) );

        $offset = ( $current_page - 1 ) * $per_page;

        $items = $wpdb->get_results( $wpdb->prepare( "SELECT * FROM {$table_name} ORDER BY created_at DESC LIMIT %d OFFSET %d", $per_page, $offset ), ARRAY_A );

        $this->_column_headers = array( $this->get_columns(), array(), $this->get_sortable_columns() );
        $this->items = $items;
    }
}

class FDP_Generated_Links_Log {

    public function __construct() {
        add_action( 'admin_menu', array( $this, 'add_submenu_page' ) );
    }

    public function add_submenu_page() {
        add_submenu_page(
            'edit.php?post_type=fluent_dynamic_page',
            __( 'Generated Links', 'fluent-dynamic-pages' ),
            __( 'Generated Links', 'fluent-dynamic-pages' ),
            'manage_options',
            'fdp-generated-links',
            array( $this, 'render_page' )
        );
    }

    public function render_page() {
        $table = new FDP_Links_List_Table();
        $table->prepare_items();
        ?>
        <div class="wrap">
            <h1 class="wp-heading-inline"><?php _e( 'Generated Dynamic Links', 'fluent-dynamic-pages' ); ?></h1>
            <p><?php _e( 'This list shows all unique links generated for Fluent Form submissions that were mapped to your dynamic webpages.', 'fluent-dynamic-pages' ); ?></p>
            <form id="fdp-links-filter" method="post">
                <input type="hidden" name="page" value="<?php echo esc_attr( $_REQUEST['page'] ); ?>" />
                <?php $table->display(); ?>
            </form>
        </div>
        <?php
    }
}
