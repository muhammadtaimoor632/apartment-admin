jQuery(document).ready(function($) {
    const $cart = $('#fdp-side-cart');
    const $trigger = $('#fdp-cart-trigger');
    const $closeBtn = $('#fdp-cart-close');
    const $overlay = $('.fdp-cart-overlay');
    const $productList = $('#fdp-products-list');
    const $checkoutBtn = $('#fdp-checkout-btn');
    const $cartCount = $('.fdp-cart-count');
    
    let itemsInCart = 0;

    // Open/Close Cart
    $trigger.on('click', function() {
        $cart.addClass('fdp-open');
        if($productList.children('.fdp-product-item').length === 0) {
            fetchProducts();
        }
    });

    $closeBtn.add($overlay).on('click', function() {
        $cart.removeClass('fdp-open');
    });

    // Fetch Products via AJAX
    function fetchProducts() {
        $.ajax({
            url: fdpCartObj.ajax_url,
            type: 'POST',
            data: {
                action: 'fdp_get_products'
            },
            success: function(response) {
                if(response.success && response.data.length > 0) {
                    $productList.empty();
                    response.data.forEach(function(product) {
                        const img = product.image ? `<img src="${product.image}" class="fdp-product-image" alt="${product.name}">` : `<div class="fdp-product-image"></div>`;
                        
                        const itemHtml = `
                            <div class="fdp-product-item">
                                ${img}
                                <div class="fdp-product-details">
                                    <h4 class="fdp-product-title">${product.name}</h4>
                                    <div class="fdp-product-price">${product.price}</div>
                                </div>
                                <button class="fdp-add-btn" data-id="${product.id}">+</button>
                            </div>
                        `;
                        $productList.append(itemHtml);
                    });
                } else {
                    $productList.html('<div style="text-align:center; color:#64748b; padding: 20px;">No requests available at the moment.</div>');
                }
            },
            error: function() {
                $productList.html('<div style="color:red; text-align:center;">Failed to load items.</div>');
            }
        });
    }

    // Add to Cart
    $(document).on('click', '.fdp-add-btn', function() {
        const $btn = $(this);
        const productId = $btn.data('id');
        
        if($btn.hasClass('loading')) return;
        
        $btn.addClass('loading').html('...');
        
        $.ajax({
            url: fdpCartObj.ajax_url,
            type: 'POST',
            data: {
                action: 'fdp_add_to_cart',
                product_id: productId,
                bedroom_number: fdpCartObj.bedroom_number
            },
            success: function(response) {
                if(response.success) {
                    $btn.removeClass('loading').html('✓').css('background', '#10b981');
                    itemsInCart++;
                    updateCartUI();
                    
                    setTimeout(() => {
                        $btn.html('+').css('background', '');
                    }, 2000);
                } else {
                    $btn.removeClass('loading').html('+');
                    alert('Error adding item.');
                }
            },
            error: function() {
                $btn.removeClass('loading').html('+');
            }
        });
    });

    function updateCartUI() {
        if(itemsInCart > 0) {
            $cartCount.text(itemsInCart).show();
            $checkoutBtn.prop('disabled', false).text(`Proceed to Checkout (${itemsInCart} items)`);
        }
    }

    // Proceed to Checkout
    $checkoutBtn.on('click', function() {
        if(itemsInCart > 0 && fdpCartObj.checkout_url) {
            // Save bedroom number to cookie so PHP can read it during WC checkout
            if(fdpCartObj.bedroom_number) {
                document.cookie = "fdp_bedroom_number=" + encodeURIComponent(fdpCartObj.bedroom_number) + "; path=/; max-age=86400"; // 1 day
            }
            $checkoutBtn.text('Redirecting...');
            window.location.href = fdpCartObj.checkout_url;
        }
    });
});
