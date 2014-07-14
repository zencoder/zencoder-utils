var drawChart = function(data, keyframes) {
  var numValues = data[0].data.length;
  var width = 960;
  var graph = new Rickshaw.Graph({
    element: document.querySelector("#area"),
    width: width,
    height: 320,
    renderer: 'line',
    series: data
  });
  graph.render();

  var legend = new Rickshaw.Graph.Legend({
      graph: graph,
      element: document.querySelector("#legend")
  });

  var hoverDetail = new Rickshaw.Graph.HoverDetail({
    xFormatter: function(x) {
        return "Frame #" + x;
    },
    graph: graph
  });

  var x_axis = new Rickshaw.Graph.Axis.X({
    graph: graph,
    pixelsPerTick: width / 10,
    tickFormat: function(n) {
        return n ;
    }
  });
  x_axis.render();

  var y_axis = new Rickshaw.Graph.Axis.Y({
    graph: graph,
    pixelsPerTick: 50,
    tickFormat: function(n) {
        return n;
    }
  });
  y_axis.render();

  var annotator = new Rickshaw.Graph.Annotate({
      graph: graph,
      element: document.getElementById('timeline')
  });

  for (i = 0; i < keyframes.length; i++) {
      annotator.add(keyframes[i], "Keyframe #"+keyframes[i]);
  }
  annotator.update();
}
