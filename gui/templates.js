// vim:ts=4:sw=4:expandtab

template_manager = (function() {
    var load = [ 'request', 'request_buffer', 'marker' ];
    var templates = {};
    var get = function(name) {
        return templates[name];
    };
    var check_complete = function(loadedcb) {
        var missing = jQuery.grep(load, function(element) {
            return (templates[element] === undefined);
        });

        if (missing.length === 0) {
            loadedcb();
        }
    };

    return function(loadedcb) {
        $.each(load, function(idx, name) {
            $.get('/templates/' + name + '.html', function(content) {
                templates[name] = content;
                check_complete(loadedcb);
            });
        });
        return {
            get: get
        };
    };
})();
