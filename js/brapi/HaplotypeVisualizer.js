(function(global, factory) {
    typeof exports === 'object' && typeof module !== 'undefined' ? module.exports = factory() :
        typeof define === 'function' && define.amd ? define(factory) :
        (global.PedigreeViewer = factory());
}(this, (function() {
    'use strict';

    function PedigreeViewer(server, auth, urlFunc) {
        var pdgv = {};
        var brapijs = BrAPI(server, auth);
        var root = null;
        var access_token = null;
        var loaded_nodes = {};
        var myTree = null;
        var locationSelector = null;

        urlFunc = urlFunc != undefined ? urlFunc : function() {
            return null
        };

        pdgv.newTree = function(stock_ids, callback) {
            root = stock_ids[0];
            loaded_nodes = {};
            var all_nodes = [];

            load_nodes(stock_ids, function(nodes) {
                [].push.apply(all_nodes, nodes);
                var mothers = nodes.map(function(d) {
                    return d.mother_id
                });
                var fathers = nodes.map(function(d) {
                    return d.father_id
                });
                var parents = mothers.concat(fathers).filter(function(d, index, self) {
                    return d !== undefined &&
                        d !== null &&
                        loaded_nodes[d] === undefined &&
                        self.indexOf(d) === index;
                });

                $.ajax({
                    url: '/ajax/haplotype_vis/marker_values',
                    type: 'POST',
                    contentType: 'application/json',
                    dataType: 'json',
                    data: JSON.stringify({
                        "marker_list": ['S5_36739', 'S7292_69', 'S13_92567'],
                        "accession_list": ['38881', '38882', '38885', '38886', '38887', '38888', '38889']
                    }),
                    success: function(data) {
                        for (var i = 0; i < all_nodes.length; i++) {
                            all_nodes[i].markers = d3.entries(JSON.parse(data.marker_values[i]));
                        }

                        createNewTree(all_nodes);
                        callback.call(pdgv);
                    }
                });
            });


        };

        pdgv.drawViewer = function(loc, draw_width, draw_height) {
            locationSelector = loc;
            drawTree(undefined, draw_width, draw_height);
        };

        function createNewTree(start_nodes) {
            myTree = d3.pedigreeTree()
                .levelWidth(340) //ADJUST
                .levelMidpoint(50)
                .nodePadding(340) //WIDTH
                .nodeWidth(20)
                .linkPadding(20)
                .vertical(true)
                .parentsOrdered(true)
                .parents(function(node) {
                    return [loaded_nodes[node.mother_id], loaded_nodes[node.father_id]].filter(Boolean);
                })
                .id(function(node) {
                    return node.id;
                })
                .groupChildless(false)
                .iterations(50)
                .data(start_nodes)
                .excludeFromGrouping([root]);
        }

        function load_nodes(stock_ids, callback) {
            var germplasm = brapijs.data(stock_ids);
            var pedigrees = germplasm.germplasm_pedigree(function(d) {
                return {
                    'germplasmDbId': d
                }
            });
            var progenies = germplasm.germplasm_progeny(function(d) {
                return {
                    'germplasmDbId': d
                }
            }, "map");
            pedigrees.join(progenies, germplasm).filter(function(ped_pro_germId) {
                if (ped_pro_germId[0] === null || ped_pro_germId[1] === null) {
                    console.log("Failed to load progeny or pedigree for " + ped_pro_germId[2]);
                    return false;
                }
                return true;
            }).map(function(ped_pro_germId) {
                var mother = null,
                    father = null;
                if (ped_pro_germId[0].parent1Type == "FEMALE") {
                    mother = ped_pro_germId[0].parent1DbId;
                }
                if (ped_pro_germId[0].parent1Type == "MALE") {
                    father = ped_pro_germId[0].parent1DbId;
                }
                if (ped_pro_germId[0].parent2Type == "FEMALE") {
                    mother = ped_pro_germId[0].parent2DbId;
                }
                if (ped_pro_germId[0].parent2Type == "MALE") {
                    father = ped_pro_germId[0].parent2DbId;
                }
                return {
                    'id': ped_pro_germId[2],
                    'mother_id': mother,
                    'father_id': father,
                    'name': ped_pro_germId[1].defaultDisplayName,
                    'children': ped_pro_germId[1].progeny.filter(Boolean).map(function(d) {
                        return d.germplasmDbId;
                    })
                };
            }).each(function(node) {
                loaded_nodes[node.id] = node;
            }).all(callback);
        }

        function drawTree(trans, draw_width, draw_height) {

            var layout = myTree();

            // Set default change-transtion to no duration
            trans = trans || d3.transition().duration(0);

            // Make wrapper(pdg)
            var wrap = d3.select(locationSelector);
            var canv = wrap.select("svg.pedigreeViewer");
            if (canv.empty()) {
                canv = wrap.append("svg").classed("pedigreeViewer", true)
                    .attr("width", draw_width)
                    .attr("height", draw_height)
                    .attr("viewbox", "0 0 " + draw_width + " " + draw_height);
            }
            var cbbox = canv.node().getBoundingClientRect();
            var canvw = cbbox.width,
                canvh = cbbox.height;
            var pdg = canv.select('.pedigreeTree');
            if (pdg.empty()) {
                pdg = canv.append('g').classed('pedigreeTree', true);
            }

            // Make background
            var bg = pdg.select('.pdg-bg');
            if (bg.empty()) {
                bg = pdg.append('rect')
                    .classed('pdg-bg', true)
                    .attr("x", -canvw * 500)
                    .attr("y", -canvh * 500)
                    .attr('width', canvw * 1000)
                    .attr('height', canvh * 1000)
                    .attr('fill', "white")
                    .attr('opacity', "0.00001")
                    .attr('stroke', 'none');
            }

            // Make scaled content/zoom groups
            var padding = 50;
            var pdgtree_width = d3.max([500, layout.x[1] - layout.x[0]]);
            var pdgtree_height = d3.max([500, layout.y[1] - layout.y[0]]);
            var centeringx = d3.max([0, (500 - (layout.x[1] - layout.x[0])) / 2]);
            var centeringy = d3.max([0, (500 - (layout.y[1] - layout.y[0])) / 2]);
            var scale = get_fit_scale(canvw, canvh, pdgtree_width, pdgtree_height, padding);
            var offsetx = (canvw - (pdgtree_width) * scale) / 2 + centeringx * scale;
            var offsety = (canvh - (pdgtree_height) * scale) / 2 + centeringy * scale;

            var content = pdg.select('.pdg-content');
            if (content.empty()) {
                var zoom = d3.zoom();
                var zoom_group = pdg.append('g').classed('pdg-zoom', true).data([zoom]);

                content = zoom_group.append('g').classed('pdg-content', true);
                content.datum({
                    'zoom': zoom
                });
                zoom.on("zoom", function() {
                    zoom_group.attr('transform', d3.event.transform);
                });
                bg.style("cursor", "all-scroll").call(zoom).call(zoom.transform, d3.zoomIdentity);
                bg.on("dblclick.zoom", function() {
                    zoom.transform(bg.transition(), d3.zoomIdentity);
                    return false;
                });

                content.attr('transform',
                    d3.zoomIdentity
                    .translate(offsetx, offsety)
                    .scale(scale)
                );
            }
            content.datum().zoom.scaleExtent([0.5, d3.max([pdgtree_height, pdgtree_width]) / 200]);
            content.transition(trans)
                .attr('transform',
                    d3.zoomIdentity
                    .translate(offsetx, offsety)
                    .scale(scale)
                );

            // Set up draw layers
            var linkLayer = content.select('.link-layer');
            if (linkLayer.empty()) {
                linkLayer = content.append('g').classed('link-layer', true);
            }
            var nodeLayer = content.select('.node-layer');
            if (nodeLayer.empty()) {
                nodeLayer = content.append('g').classed('node-layer', true);
            }

            // Link curve generators
            var stepline = d3.line().curve(d3.curveStepAfter);
            var curveline = d3.line().curve(d3.curveBasis);
            var build_curve = function(d) {
                if (d.type == "parent->mid") return curveline(d.path);
                if (d.type == "mid->child") return stepline(d.path);
            };

            // Draw nodes
            var nodes = nodeLayer.selectAll('.node')
                .data(layout.nodes, function(d) {
                    return d.id;
                });
            var newNodes = nodes.enter().append('g')
                .classed('node', true)
                .attr('transform', function(d) {
                    var begin = d;
                    if (d3.event && d3.event.type == "click") {
                        begin = d3.select(d3.event.target).datum();
                    }
                    return 'translate(' + begin.x + ',' + begin.y + ')'
                });
            var nodeNodes = newNodes.filter(function(d) {
                return d.type == "node";
            });

            nodeNodes.append('rect').classed("node-name-wrapper", true)
                .attr('fill', "white")
                .attr('stroke', "grey")
                .attr('stroke-width', 2)
                .attr("width", 200)
                .attr("height", 20)
                .attr("y", 0)
                .attr("rx", 10)
                .attr("ry", 10)
                .attr("x", -100);

            // Draw markers
            var markerNodes = nodeNodes.selectAll('.markers')
                .data(function(d) {
                    return d.value.markers;
                })
                .enter().append("g")
                .classed('markers', true);

            markerNodes.append('rect')
                .classed('.marker-name-wrapper', true)
                .attr('fill', "white")
                .attr('stroke', function(d) {
                    if (d.value == '0') {
                        return d3.color("#664cbe");
                    } else if (d.value == '1') {
                        return d3.color("#1eb8d0");
                    } else {
                        return d3.color("#9cf257");
                    }
                })
                .attr('stroke-width', 2)
                .attr('fill', function(d) {
                    if (d.value == '0') {
                        return d3.color("#664cbe");
                    } else if (d.value == '1') {
                        return d3.color("#1eb8d0");
                    } else {
                        return d3.color("#9cf257");
                    }
                })
                .style("opacity", .4)
                .attr("width", 110)
                .attr("height", 20)
                .attr("y", function(d, i) {
                    return 22 * i;
                })
                .attr("rx", 10)
                .attr("ry", 10)
                .attr("x", 70);

            markerNodes.append('text')
                .classed('marker-names', true)
                .attr("y", function(d, i) {
                    return 22 * i + 15;
                })
                .attr("x", 80)
                .text(function(d, i) {
                    return d.key + ': ' + d.value;
                })
                .attr('fill', 'black');

            // Set node width to text width
            markerNodes.each(function(d) {
                var nn = d3.select(this);
                var ctl = nn.select('.marker-names').node().getComputedTextLength();
                var w = ctl + 20;
                nn.select('.marker-name-wrapper')
                    .attr("width", w)
                    .attr("x", -w / 2);
            });

            // Draw links
            var nodeUrlLinks = nodeNodes.filter(function(d) {
                    var url = urlFunc(d.id);
                    if (url !== null) {
                        d.url = url;
                        return true;
                    }
                    return false;
                })
                .append('a')
                .attr('href', function(d) {
                    return urlFunc(d.id);
                })
                .attr('target', '_blank')
                .append('text').classed('node-name-text', true)
                .attr('y', 15)
                .attr('text-anchor', "middle")
                .text(function(d) {
                    return d.value.name;
                })
                .attr('fill', "black");
            nodeNodes.filter(function(d) {
                    return d.url === undefined;
                })
                .append('text').classed('node-name-text', true)
                .attr('y', 15)
                .attr('text-anchor', "middle")
                .text(function(d) {
                    return d.value.name;
                })
                .attr('fill', "black");

            // Set marker width to text width
            nodeNodes.each(function(d) {
                var nn = d3.select(this);
                var ctl = nn.select('.node-name-text').node().getComputedTextLength();
                var w = ctl + 20;
                nn.select('.node-name-wrapper')
                    .attr("width", w)
                    .attr("x", -w / 2);
            });


            // Link colors
            var link_color = function(d) {
                if (d.type == "mid->child") return d3.rgb(115, 60, 170);
                if (d.type == "parent->mid") {
                    // If its the first parent, red. Otherwise, blue.
                    var representative = d.sinks[0].type == "node-group" ?
                        d.sinks[0].value[0].value :
                        d.sinks[0].value;
                    if (representative.mother_id == d.source.id) {
                        return d3.rgb(240, 30, 30);
                    } else {
                        return d3.rgb(65, 85, 220);
                    }
                }
                return 'gray';
            };

            // Make links
            var links = linkLayer.selectAll('.link')
                .data(layout.links, function(d) {
                    return d.id;
                });
            var newLinks = links.enter().append('g')
                .classed('link', true);
            newLinks.append('path')
                .attr('d', function(d) {
                    var begin = (d.sink || d.source);
                    if (d3.event && d3.event.type == "click") {
                        begin = d3.select(d3.event.target).datum();
                    }
                    return curveline([
                        [begin.x, begin.y],
                        [begin.x, begin.y],
                        [begin.x, begin.y],
                        [begin.x, begin.y]
                    ]);
                })
                .attr('fill', 'none')
                .attr('stroke', link_color)
                .attr('opacity', function(d) {
                    if (d.type == "parent->mid") return 0.7;
                    return 0.999;
                })
                .attr('stroke-width', 4);
            var allLinks = newLinks.merge(links);
            allLinks.transition(trans).select('path').attr('d', build_curve);
        }

        return pdgv;
    }

    function get_fit_scale(w1, h1, w2, h2, pad) {
        w1 -= pad * 2;
        h1 -= pad * 2;
        if (w1 / w2 < h1 / h2) {
            return w1 / w2;
        } else {
            return h1 / h2;
        }
    }

    return PedigreeViewer;

})));