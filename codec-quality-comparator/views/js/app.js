var gengraph = function(svg, values, maxlen, keyframes, width, height, margin, domain, color, label) {

  var x = d3.scale.linear()
      .domain([0, maxlen])
      .range([0, width]);

  var y = d3.scale.linear()
      .domain(domain)
      .range([height, 0]);

  var xAxis = d3.svg.axis()
    .scale(x)
    .innerTickSize(-height)
    .tickPadding(10)
    .tickFormat("")
    .tickValues(keyframes)
    .orient("bottom");

  var yAxis = d3.svg.axis()
    .scale(y)
    .ticks(3)
    .orient("right");

  var line = d3.svg.line()
    .interpolate("monotone")
    .x(function(d) { return x(d.x); })
    .y(function(d) { return y(d.y); });

  svg = svg.append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

  svg.append("g")
      .attr("class", "x axis")
      .attr("transform", "translate(0," + height + ")")
      .call(xAxis)
      .selectAll("text");

  svg.append("g")
      .attr("class", "y axis")
      .attr("transform", "translate(" + width + ",0)")
      .call(yAxis)
      .append("text")
        .attr("y", 10)
        .attr("x", -10)
        .attr("fill", color)
        .style("text-anchor", "end")
        .text(label);

  svg.append("path")
    .datum(values)
    .attr("class", "line")
    .attr("stroke", color)
    .attr("stroke-width", "1.5px")
    .attr("stroke-opacity", "0.7")
    .attr("fill", "none")
    .attr("d", line);

  var hover = svg.append("g")
    .style("display", "none");

  hover.append("text")
    .attr("dy", "-3.5em");

  svg.append("rect")
    .attr("fill", "none")
    .attr("pointer-events", "all")
    .attr("width", width)
    .attr("height", height)
    .on("mouseover", function() {
      hover.style("display", null);
    })
    .on("mouseout", function() {
      hover.style("display", "none");
    })
    .on("mousemove", function() {
      var x0 = x.invert(d3.mouse(this)[0]);
      var bisector = d3.bisector(function(d) { return d.x }).left
      var i = bisector(values, x0, 1);
      d = values[i];
      hover.attr("transform", "translate(" + x(d.x) + "," + y(d.y) + ")");
      hover.select("text").text("(" + Math.ceil(x0) + "," + d.y + ")");
      videojs('reference-video').currentTime(Math.ceil(x0) / 29.97)
      videojs('degraded-video').currentTime(Math.ceil(x0) / 29.97)
    });
}

var drawChart = function(data, keyframes, minmaxes) {
  var margin = {
      top: 20,
      right: 50,
      bottom: 30,
      left: 40
    },
    width = 1280 - margin.left - margin.right,
    height = 100;

  var svg = d3.select("body").append("svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", 500 + margin.top + margin.bottom)

  svg.append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top/2 + ")")
    .append("text")
    .text("Keyframes = " + keyframes)

  var frames = data[0].data.length;
  for (i = 0; i < data.length; i++ ) {
    var color = data[i].color,
        label = data[i].name,
        values = data[i].data;

    var domain;
    if (i + 2 >= data.length) {
      domain = [d3.min(values, function(x) { return x.y }),
                d3.max(values, function(x) { return x.y })]
    } else {
      domain = [minmaxes[(i % 3) * 2], minmaxes[(i % 3) * 2 + 1]]
    }

    if (i + 3 > data.length) { keyframes = [0] }

    gengraph(svg, values, frames, keyframes, width, height, margin, domain, color, label);
    margin.top += 105;
    if (i % 3 == 2 && (i + 3 < data.length)) { margin.top -= 315 }
    if (i + 3 >= data.length) { margin.top += 5 }
  }
}
