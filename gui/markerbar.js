// vim:ts=4:sw=4:expandtab

markerbar = (function() {
    function update() {
        var prev = $('.marker:above-the-top:last');
        if (prev.length > 0) {
            $('#prevmarker').text('← "' + prev.text() + '"');
            $('#prevmarker').click(function() {
                $.scrollTo(prev);
            });
        } else {
            $('#prevmarker').text('');
        }
        var next = $('.marker:below-the-fold:first');
        if (next.length > 0) {
            $('#nextmarker').text('"' + next.text() + '" →');
            $('#nextmarker').click(function() {
                $.scrollTo(next);
            });
        } else {
            $('#nextmarker').text('');
        }
    }

    return function() {
        console.log('markerbar init!');
        $(window).scroll(function () {
            update();
        });

        return {
            update: update
        };
    };
})();
