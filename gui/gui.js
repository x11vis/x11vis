// vim:ts=4:sw=4:expandtab

var tmpl;

// Add an econtains selector which checks for equality
$.expr[":"].econtains = function(obj, index, meta, stack){
    return (obj.textContent || obj.innerText || $(obj).text() || "").toLowerCase() == meta[3].toLowerCase();
}

$(document).ready(function() {
    $("#status").replaceWith('x11vis started');

    // Create a global instance of the template manager
    tmpl = template_manager(function() {
        console.log("templates loaded");

        $.getJSON('/gen/predefined_atoms.json', function(indata) {
            console.log("Predefined atoms loaded");
            var vis = x11vis();
            vis.process_cleverness(indata);

            console.log("Requesting JSON trace file");
            var at_req = (new Date).getTime();
            $.getJSON('/tracedata/output.json', function(indata) {
                var got_data = (new Date).getTime();
                console.log('JSON parsed in ' + (got_data - at_req) + 'ms');
                vis.process_json(indata);
                var after_proc = (new Date).getTime();
                console.log('processing took ' + (after_proc - got_data) + 'ms');
            });
        });
    });


    // TODO: re-enable
    //var window_properties = '\
    //<div class="window_prop">\
    //<table width="100%">\
    //<tr><th>X11 ID</th><td class="id"></td></tr>\
    //<tr><th>Class</th><td class="class"></td></tr>\
    //<tr><th>Title</th><td class="title"></td></tr>\
    //</table>\
    //</div>\
    //';

    //// expand function for X11 window IDs
    //$('.xwindow').click(function() {
    //    var id = $(this).attr('id');
    //    var d = details[id];
    //    var props = $(window_properties);
    //    props.find(".id").append(id);
    //    props.find(".title").append(d['name']);
    //    $("#inspector").append(props);
    //});
});

