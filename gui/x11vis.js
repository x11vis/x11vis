// vim:ts=4:sw=4:expandtab

x11vis = (function() {
    var used_names = [];
    var details = {};

    function type_to_color(type) {
        if (type === 'event') {
            return '#ffffc0';
        } else if (type === 'reply') {
            return '#c0ffc0';
        } else if (type === 'error') {
            return '#ffc0c0';
        } else {
            return '#c0c0c0';
        }
    }

    // TODO: formatting needs to be more beautiful
    function detail_obj_to_html(obj, indent) {
        var result = '';
        $.each(obj, function(key, val) {
            var formatted_value;
            if (typeof(val) === 'object') {
                formatted_value = detail_obj_to_html(val, indent + 1);
            } else {
                formatted_value = val;
            }
            result += '<p style="margin-left: ' + indent + 'em"><strong>' + key + '</strong>: ' + formatted_value + '</p>';
        });
        return result;
    }

    function toggle_expand_packet(pkt) {
        var html = $(pkt).find('.moredetails')

        // if it's visible, hide it
        if (html.css('display') === 'block') {
            html.css('display', 'none');
        } else {
            // otherwise, format the details (if not expanded) and show it 
            if ($(pkt).data('expanded') === undefined) {
                html.append(detail_obj_to_html($(pkt).data('moredetails'), 0));
                $(pkt).data('expanded', true);
            }

            html.css('display', 'block');
        }
    }

    function create_request_layout(obj) {
        // concat'ing strings instead of using the DOM saves us ~ 350 ms
        // (measured with 547 bursts of a typical i3 startup)

        var html = '<div class="request singlepacket" style="background-color: ' + type_to_color(obj.type) + '">\
        <div class="expandbtn"></div>\
        <span class="sequence">' + obj.seq + '</span>\
        <span class="name">' + obj.name + '</span>\
        <span class="details">' + parse_detail(obj.details) + '</span>\
        <span class="moredetails"></span>\
        </div>\
        ';
        var rdiv = $(html);

        // store object type and moredetails for later (used type_to_color and
        // detail_obj_to_html, respectively)
        rdiv.data('type', obj.type);
        rdiv.data('moredetails', obj.moredetails);

        return rdiv;
    }

    function parse_detail(detail) {
        var result = detail;
        var matches = detail.match(/%([^%]+)%/g) || [];
        matches.forEach(function(m) {
            var id = m.replace(/%/g, '');
            result = result.replace(m, '<span class="id_name" id="' + id + '"></span>');
        });
        return result;
    }

    function save_cleverness(obj) {
        //console.log('obj is clever: ' + obj.id + ' to ' + obj.title);
        var title = obj.title;
        var cnt = 2;
        while ($.inArray(title, used_names) !== -1) {
            title = obj.title + ' (' + cnt + ')';
            cnt = cnt + 1;
        }
        obj.title = title;
        used_names.push(title);
        details[obj.id] = obj;
    }

    function handle_marker(marker) {
        var div = $(tmpl.get('marker'));
        div.find("span.name").replaceWith(marker.title);
        $('body').append(div);
    }

    function handle_burst(burst) {
        // TODO: what about zero-length bursts?
        if (burst.packets.length === 0) {
            return;
        }
        var div = $(tmpl.get('request_buffer'));
        div.find(".request_info").append(burst.elapsed);

        // TODO: add direction also to burst
        var is_reply = false;
        $.each(burst.packets, function(idx, elm) {
            if (elm.type === 'reply') {
                is_reply = true;
            } else if (elm.type === 'event') {
                is_reply = true;
            }
        });
        if (is_reply) {
            div.css('margin-left', '2em');
            div.find(".client").replaceWith(parse_detail('%conn_' + burst.fd + '%←'));
        } else {
            div.find(".client").replaceWith(parse_detail('%conn_' + burst.fd + '%→'));
            div.css('margin-right', '2em');
        }

        burst.packets.forEach(function(obj) {
            if (obj.type === 'cleverness') {
                save_cleverness(obj);
            } else {
                div.append(create_request_layout(obj));
            }
        });

        $('body').append(div);
    }

    function update_hide_packets() {
        // add all event types (once) to the 'hide'-panel
        // TODO: group by type
        // TODO: start with collapsed 'hide' panel
        var t = _.map($('span.name'), function(elm) { return $(elm).text(); });
        t.sort();
        $.each(_.uniq(t, true), function(idx, elm) {
            var cb = $('<input type="checkbox" class="display_cb" id="display_cb_' + idx + '" checked="checked"><label for="display_cb_' + idx + '">' + elm + '</label><br>');
            cb.data('element', elm);
            $('div#display').append(cb);
        });

        $('input.display_cb').click(function() {
            var elm = $(this).data('element');
            $("span.name:contains('" + elm + "')")
                .parent()
                .css('display', ($(this).attr('checked') ? 'block' : 'none'));
        });
    }

    function update_hide_clients() {
        // add all clients (once) to 'hide' panel
        t = _.map($('div.reqbuf .header .id_name'), function (elm) { return $(elm).attr('id'); });
        t.sort();
        $.each(_.uniq(t, true), function(idx, elm) {
            console.log('client: ' + elm);
            var cb = $('<input type="checkbox" class="client_cb" id="client_cb_' + idx + '" checked="checked"><label for="client_cb_' + idx + '">' + parse_detail('%' + elm + '%') + '</label><br>');
            cb.data('element', elm);
            $('div#filter_clients').append(cb);
        });

        $('input.client_cb').click(function() {
            var elm = $(this).data('element');
            $('div.reqbuf .header .id_name#' + elm)
                .parent()
                .parent()
                .css('display', ($(this).attr('checked') ? 'block' : 'none'));
        });
    }

    function fold_boring_packets() {
        // TODO: marking packets for folding could be done in the interceptor
        // go through all reqbufs and fold series of 'boring' requests (like InternAtom)
        var boring_packets = [ 'InternAtom', 'GrabKey', 'ImageText8', 'ImageText16' ];
        $('div.reqbuf').each(function() {
            var last_name = '';
            var to_fold = [];
            var samecnt = 0;
            var singlepkts = $(this).find('div.singlepacket span.name');
            var len = singlepkts.length;
            if (len < 5) {
                return;
            }
            var c = len;
            while (c--) {
                var name = $(singlepkts[c]).text();
                if ($.inArray(name, to_fold) !== -1) {
                    continue;
                }
                samecnt = (last_name === name ? samecnt + 1 : 0);
                if (samecnt === 5 && $.inArray(last_name, boring_packets) !== -1) {
                    // more than 5 packets of the same type, fold them
                    to_fold.push(last_name);
                }
                last_name = name;
            }

            var that = this;
            $.each(to_fold, function(idx, elm) {
                var folded = $('<div class="folded"></div>');
                var info = $('<div class="folded_info"><img src="/toggle-expand.gif"> lots of <strong>' + elm + '</strong></div>');
                var to_expand = $('<div class="to_expand" style="display: none"></div>');
                var elements = $(that).find('div.singlepacket span.name:econtains("' + elm + '")').parent();
                var type = elements.first().data('type');
                folded.data('type', type);
                folded.css('background-color', type_to_color(type));
                info.append(' (' + elements.size() + ' packets folded)');
                elements.wrapAll(to_expand);
                $(that).find('.to_expand')
                    .wrap(folded)
                    .parent()
                    .prepend(info);

            });
        });
    }

    function setup_expand_button() {
        // set up the expand button
        $('.singlepacket').live('click', function() {
            toggle_expand_packet(this);
        });

        $('.folded_info').live('click', function() {
            var to_expand = $(this).parent().find('.to_expand');
            if (to_expand.css('display') === 'block') {
                to_expand.css('display', 'none');
            } else {
                to_expand.css('display', 'block');
            }
        });

        // TODO: only show button if the request has details
        $('.request.singlepacket, .folded').each(function() {
            $(this).hover(function() {
                var expandBtn = $(this).children('.expandbtn');
                // if the expand image is not yet loaded, add it
                if (expandBtn.find('img').size() === 0) {
                    expandBtn.append($('<img src="/toggle-expand.gif">'));
                }
                expandBtn.find('img').css('display', 'inline');
                $(this).css('background-color', '#eff8c6');
            }, function() {
                $(this).find('.expandbtn img').css('display', 'none');
                $(this).css('background-color', type_to_color($(this).data('type')));
            });
        });
    }

    function display_cleverness() {
        // resolve all the cleverness placeholders
        $('span.id_name').each(function() {
            var id = $(this).attr('id');
            if (details[id] !== undefined) {
                $(this).append(details[id].title);
                if (details[id].idtype === 'atom') {
                    $(this).css('background-color', '#82caff');
                } else if (details[id].idtype === 'font') {
                    $(this).css('background-color', '#f87217');
                } else if (details[id].idtype === 'pixmap') {
                    $(this).css('background-color', '#d462ff');
                } else if (details[id].idtype === 'gcontext') {
                    $(this).css('background-color', '#f433ff');
                } else {
                    $(this).css('background-color', '#f75d59');
                }
            } else {
                $(this).append(id);
            }
        });
    }

    var process_json = function(json) {
        var len = json.length;
        for (var c = 0; c < len; c++) {
            var obj = json[c];
            if (obj.type === 'cleverness') {
                save_cleverness(obj);
            } else if (obj.type === 'marker') {
                handle_marker(obj);
            } else {
                handle_burst(obj);
            }
        }

        update_hide_packets();
        update_hide_clients();
        fold_boring_packets();
        setup_expand_button();
        display_cleverness();

        // initialize the markerbar
        markerbar().update();
    };

    var process_cleverness = function(json) {
        json.forEach(function(obj) {
            save_cleverness(obj);
        });
    };

    return function() {
        return {
            process_json: process_json,
            process_cleverness: process_cleverness
        };
    };
})();
