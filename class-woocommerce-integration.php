<?php
if (!defined('ABSPATH')) {
    exit;
}

class FDP_WooCommerce_Integration {

    public function __construct() {
        // Enqueue assets for the side cart
        add_action('wp_enqueue_scripts', array($this, 'enqueue_assets'));
        
        // Output side cart HTML in footer
        add_action('wp_footer', array($this, 'render_side_cart'));

        // Handle WooCommerce Checkout to capture Bedroom Number
        add_action('woocommerce_checkout_update_order_meta', array($this, 'save_bedroom_number_to_order'));
        add_action('woocommerce_store_api_checkout_update_order_from_request', array($this, 'save_bedroom_number_to_order_blocks'), 10, 2);

        // Register custom REST API endpoint for the app
        add_action('rest_api_init', array($this, 'register_guest_requests_endpoint'));
        
        // Custom AJAX endpoints for the cart
        add_action('wp_ajax_fdp_get_products', array($this, 'get_products'));
        add_action('wp_ajax_nopriv_fdp_get_products', array($this, 'get_products'));
        
        add_action('wp_ajax_fdp_add_to_cart', array($this, 'add_to_cart'));
        add_action('wp_ajax_nopriv_fdp_add_to_cart', array($this, 'add_to_cart'));
    }

    public function enqueue_assets() {
        // Only load on our dynamic pages
        if (!is_singular('fluent_dynamic_page')) {
            return;
        }

        wp_enqueue_style('fdp-side-cart-css', FF_DYNAMIC_PAGES_URL . 'assets/side-cart.css', array(), FF_DYNAMIC_PAGES_VERSION);
        wp_enqueue_script('fdp-side-cart-js', FF_DYNAMIC_PAGES_URL . 'assets/side-cart.js', array('jquery'), FF_DYNAMIC_PAGES_VERSION, true);

        // Extract Bedroom Number from Fluent Forms submission if available
        global $post;
        $bedroom_number = get_the_title($post->ID); 
        
        if(isset($_GET['fdp_hash'])) {
            global $wpdb;
            $hash = sanitize_text_field($_GET['fdp_hash']);
            $table_name = $wpdb->prefix . 'fdp_generated_links';
            $link_record = $wpdb->get_row($wpdb->prepare("SELECT submission_id FROM {$table_name} WHERE hash = %s", $hash));
            if($link_record) {
                $submission = $wpdb->get_row($wpdb->prepare("SELECT response FROM {$wpdb->prefix}fluentform_submissions WHERE id = %d", $link_record->submission_id));
                if($submission) {
                    $data = json_decode($submission->response, true);
                    if(isset($data['apartment_number'])) {
                        $bedroom_number = $data['apartment_number'];
                    } elseif (isset($data['bedroom_number'])) {
                        $bedroom_number = $data['bedroom_number'];
                    }
                }
            }
        }

        wp_localize_script('fdp-side-cart-js', 'fdpCartObj', array(
            'ajax_url' => admin_url('admin-ajax.php'),
            'checkout_url' => function_exists('wc_get_checkout_url') ? wc_get_checkout_url() : '',
            'bedroom_number' => $bedroom_number
        ));
    }

    public function render_side_cart() {
        if (!is_singular('fluent_dynamic_page')) {
            return;
        }
        ?>
        <!-- Side Cart Trigger Button -->
        <button id="fdp-cart-trigger" class="fdp-cart-trigger">
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"></path><line x1="3" y1="6" x2="21" y2="6"></line><path d="M16 10a4 4 0 0 1-8 0"></path></svg>
            <span class="fdp-cart-count" style="display:none;">0</span>
        </button>

        <!-- Side Cart Drawer -->
        <div id="fdp-side-cart" class="fdp-side-cart">
            <div class="fdp-cart-overlay"></div>
            <div class="fdp-cart-panel">
                <div class="fdp-cart-header">
                    <h2>Request Extras</h2>
                    <button id="fdp-cart-close" class="fdp-cart-close">&times;</button>
                </div>
                <div class="fdp-cart-body">
                    <div id="fdp-products-list" class="fdp-products-list">
                        <div class="fdp-loading">Loading available requests...</div>
                    </div>
                </div>
                <div class="fdp-cart-footer">
                    <button id="fdp-checkout-btn" class="fdp-checkout-btn" disabled>Proceed to Checkout</button>
                </div>
            </div>
        </div>
        <?php
    }

    public function get_products() {
        if (!class_exists('WooCommerce')) {
            wp_send_json_error('WooCommerce not installed');
        }

        $args = array(
            'status' => 'publish',
            'limit' => 20,
        );
        $products = wc_get_products($args);
        
        $data = array();
        foreach ($products as $product) {
            $image_id  = $product->get_image_id();
            $image_url = $image_id ? wp_get_attachment_image_url($image_id, 'thumbnail') : '';
            
            $data[] = array(
                'id' => $product->get_id(),
                'name' => $product->get_name(),
                'price' => $product->get_price_html(),
                'image' => $image_url,
                'raw_price' => $product->get_price()
            );
        }

        wp_send_json_success($data);
    }

    public function add_to_cart() {
        if (!class_exists('WooCommerce')) {
            wp_send_json_error('WooCommerce not installed');
        }

        $product_id = isset($_POST['product_id']) ? intval($_POST['product_id']) : 0;
        $bedroom_number = isset($_POST['bedroom_number']) ? sanitize_text_field($_POST['bedroom_number']) : '';
        
        if ($product_id > 0) {
            WC()->cart->add_to_cart($product_id);
            if (!empty($bedroom_number) && isset(WC()->session)) {
                WC()->session->set('fdp_bedroom_number', $bedroom_number);
            }
            wp_send_json_success('Added to cart');
        } else {
            wp_send_json_error('Invalid product');
        }
    }

    public function save_bedroom_number_to_order($order_id) {
        $bedroom_number = '';
        if (isset($_COOKIE['fdp_bedroom_number'])) {
            $bedroom_number = sanitize_text_field(stripslashes($_COOKIE['fdp_bedroom_number']));
        } elseif (isset(WC()->session) && WC()->session->get('fdp_bedroom_number')) {
            $bedroom_number = WC()->session->get('fdp_bedroom_number');
        }

        if (!empty($bedroom_number)) {
            update_post_meta($order_id, '_fdp_bedroom_number', $bedroom_number);
            
            $order = wc_get_order($order_id);
            if ($order) {
                $order->add_order_note("Guest Request for Bedroom/Apartment: " . $bedroom_number);
            }
        }
    }

    public function save_bedroom_number_to_order_blocks($order, $request) {
        $bedroom_number = '';
        if (isset($_COOKIE['fdp_bedroom_number'])) {
            $bedroom_number = sanitize_text_field(stripslashes($_COOKIE['fdp_bedroom_number']));
        } elseif (isset(WC()->session) && WC()->session->get('fdp_bedroom_number')) {
            $bedroom_number = WC()->session->get('fdp_bedroom_number');
        }
        
        if (!empty($bedroom_number)) {
            $order->update_meta_data('_fdp_bedroom_number', $bedroom_number);
            $order->add_order_note("Guest Request for Bedroom/Apartment: " . $bedroom_number);
        }
    }

    public function register_guest_requests_endpoint() {
        register_rest_route('fluent_dynamic/v1', '/guest-requests', array(
            'methods' => 'GET',
            'callback' => array($this, 'get_guest_requests_api'),
            'permission_callback' => '__return_true'
        ));
    }

    public function get_guest_requests_api($request) {
        if (!class_exists('WooCommerce')) {
            return new WP_Error('wc_missing', 'WooCommerce is not active', array('status' => 500));
        }

        $args = array(
            'limit' => 20,
            'orderby' => 'date',
            'order' => 'DESC',
            'return' => 'objects',
        );

        $orders = wc_get_orders($args);
        $results = array();

        foreach ($orders as $order) {
            $bedroom_number = $order->get_meta('_fdp_bedroom_number');
            if (empty($bedroom_number)) {
                $bedroom_number = 'Direct Order';
            }
            
            $items = array();
            foreach ($order->get_items() as $item_id => $item) {
                $items[] = array(
                    'product_name' => $item->get_name(),
                    'quantity' => $item->get_quantity(),
                    'total' => $item->get_total()
                );
            }

            $results[] = array(
                'order_id' => $order->get_id(),
                'status' => $order->get_status(),
                'date' => $order->get_date_created()->date('Y-m-d H:i:s'),
                'bedroom_number' => $bedroom_number,
                'total' => $order->get_total(),
                'items' => $items
            );
        }

        return rest_ensure_response($results);
    }
}
