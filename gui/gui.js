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

        console.log("Requesting JSON trace file");
        $.getJSON('/tracedata/output.json', function(indata) {
            console.log("JSON trace file loaded, rendering...");
            var vis = x11vis();
            vis.process_json(indata);
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

