/* ===================================================================
   FDP Dynamic Pages — Frontend Widget Interactions
   =================================================================== */
(function () {
    'use strict';

    document.addEventListener('DOMContentLoaded', function () {

        // ── Accordion Toggle ──────────────────────────────────────
        document.querySelectorAll('.fdp-accordion-header').forEach(function (btn) {
            btn.addEventListener('click', function () {
                var item = this.closest('.fdp-accordion-item');
                item.classList.toggle('fdp-active');
            });
        });

        // ── Video Modal ───────────────────────────────────────────
        var modal    = document.getElementById('fdp-video-modal');
        if (!modal) return;

        var player   = document.getElementById('fdp-video-player');
        var closeBtn = document.getElementById('fdp-modal-close');

        function getEmbedUrl(url) {
            var videoId = '';
            if (url.indexOf('youtu.be/') !== -1) {
                videoId = url.split('youtu.be/')[1].split('?')[0].split('&')[0];
            } else if (url.indexOf('youtube.com/watch') !== -1) {
                try { videoId = new URL(url).searchParams.get('v') || ''; } catch (e) {}
            } else if (url.indexOf('youtube.com/embed/') !== -1) {
                videoId = url.split('youtube.com/embed/')[1].split('?')[0];
            } else if (url.indexOf('youtube.com/shorts/') !== -1) {
                videoId = url.split('youtube.com/shorts/')[1].split('?')[0].split('&')[0];
            }
            return videoId
                ? 'https://www.youtube.com/embed/' + videoId + '?autoplay=1&rel=0'
                : url;
        }

        function openModal(rawUrl) {
            if (player) player.src = getEmbedUrl(rawUrl);
            modal.classList.add('fdp-modal-open');
            document.body.style.overflow = 'hidden';
        }

        function closeModal() {
            modal.classList.remove('fdp-modal-open');
            if (player) player.src = '';
            document.body.style.overflow = '';
        }

        // Attach to all video links (including those inside accordions)
        document.querySelectorAll('.fdp-video-link').forEach(function (link) {
            link.addEventListener('click', function (e) {
                e.preventDefault();
                openModal(this.getAttribute('data-video-url') || '');
            });
        });

        if (closeBtn) closeBtn.addEventListener('click', closeModal);

        modal.addEventListener('click', function (e) {
            if (e.target === modal) closeModal();
        });

        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') closeModal();
        });

        // ── Dynamic Popup ─────────────────────────────────────────
        var dynamicPopup = document.getElementById('fdp-dynamic-popup-modal');
        if (dynamicPopup) {
            var popupCloseBtn = dynamicPopup.querySelector('.fdp-popup-close-btn');
            var triggerType = dynamicPopup.getAttribute('data-trigger');
            var delaySecs = parseInt(dynamicPopup.getAttribute('data-delay'), 10) || 0;

            function openDynamicPopup() {
                var container = dynamicPopup.closest('.fdp-dynamic-section-container');
                if (container && window.getComputedStyle(container).display === 'none') {
                    return;
                }
                dynamicPopup.classList.add('fdp-modal-open');
                document.body.style.overflow = 'hidden';
            }

            function closeDynamicPopup() {
                dynamicPopup.classList.remove('fdp-modal-open');
                document.body.style.overflow = '';
            }

            if (popupCloseBtn) {
                popupCloseBtn.addEventListener('click', closeDynamicPopup);
            }

            dynamicPopup.addEventListener('click', function(e) {
                if (e.target === dynamicPopup) closeDynamicPopup();
            });

            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') closeDynamicPopup();
            });

            if (triggerType === 'page_load') {
                setTimeout(openDynamicPopup, delaySecs * 1000);
            } else if (triggerType === 'button_click') {
                document.querySelectorAll('.fdp-popup-trigger-btn').forEach(function(btn) {
                    btn.addEventListener('click', function(e) {
                        e.preventDefault();
                        openDynamicPopup();
                    });
                });
            }
        }
    });
}());
