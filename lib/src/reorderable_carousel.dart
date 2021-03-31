import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A carousel that can be re-ordered by dragging the elements around.
class ReorderableCarousel extends StatefulWidget {
  /// The number of items in the carousel.
  final int numItems;

  /// Callback for when the user presses the "+" button. The given index
  /// indicates where the new item should be inserted at.
  final FutureOr<void> Function(int index) addItemAt;

  /// Builder for creating the items of the carousel.
  /// [itemWidth] indicates the maximum amount of width alloted for the item
  ///
  /// [index] is the index of the item to be built
  ///
  /// [isSelected] whether or not the item is selected. This will be true if the
  ///   item has been tapped on, or if it's currently being dragged
  final Widget Function(double itemWidth, int index, bool isSelected)
      itemBuilder;

  /// Called after the items have been reordered. Both [oldIndex] and [newIndex]
  /// will be > 0 and < numItems
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Called whenever a new item is selected.
  final void Function(int selectedIndex)? onItemSelected;

  /// The fraction of the available width of the screen that the item will take
  /// up.
  /// The item's width will be calculated like so (a [LayoutBuilder] is used):
  /// constraints.maxWidth / [itemWidthFraction]
  ///
  /// Must be >= 1.0
  final double itemWidthFraction;

  /// Creates a new [ReorderableCarousel]
  ReorderableCarousel({
    required this.numItems,
    required this.addItemAt,
    required this.itemBuilder,
    required this.onReorder,
    this.onItemSelected,
    this.itemWidthFraction = 3,
    Key? key,
  })  : assert(numItems >= 1, "You need at least one item"),
        assert(itemWidthFraction >= 1),
        super(key: key);

  @override
  _ReorderableCarouselState createState() => _ReorderableCarouselState();
}

class _ReorderableCarouselState extends State<ReorderableCarousel> {
  bool _dragInProgress = false;

  double _itemMaxWidth = -1;
  double _startingOffset = 0;
  double _endingOffset = 0;

  // includes padding around icon button
  final double _iconSize = 24 + 16.0;
  late ScrollController _controller;
  int _selectedIdx = 0;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double width = constraints.maxWidth / widget.itemWidthFraction;
        if (width != _itemMaxWidth) {
          _itemMaxWidth = width;
          _startingOffset = (constraints.maxWidth / 2) - (_itemMaxWidth / 2);
          _endingOffset = max(0, _startingOffset - _iconSize);

          // whenever the size of this widget changes, we'll rescroll to center
          // the selected item.
          _scrollToBox(_selectedIdx);
        }

        var children = [
          SizedBox(
            width: _startingOffset,
          ),
          for (int i = 0; i < widget.numItems; i++)
            GestureDetector(
              onTap: () {
                _scrollToBox(i);
              },
              child: ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: _itemMaxWidth),
                child: widget.itemBuilder(_itemMaxWidth, i, i == _selectedIdx),
              ),
            ),
          SizedBox(
            width: _endingOffset,
          ),
        ];

        return ReorderableList(
          // We want all the pages to be cached. This also
          // alleviates a problem where scrolling would get broken if
          // a page changed a position by more than ~4.
          cacheExtent: (_itemMaxWidth + _iconSize) * widget.numItems,
          controller: _controller,
          scrollDirection: Axis.horizontal,
          onReorder: (oldIndex, newIndex) {
            // compensate for the leading space
            oldIndex--;
            newIndex--;
            if (newIndex > oldIndex) {
              newIndex--;
            }

            // clamp, in the event that the reorder involves the
            // leading spaces. Removing 1 to accommodate the fact that the item
            // will be removed as part of reordering.
            newIndex = newIndex.clamp(0, widget.numItems - 1);
            widget.onReorder(oldIndex, newIndex);

            // Color swap = colors.removeAt(oldIndex);
            // colors.insert(newIndex, swap);
            setState(() {
              _dragInProgress = false;

              _updateSelectedIndex(newIndex);

              _scrollToBox(newIndex);
            });
          },
          itemCount: children.length,
          itemBuilder: (context, i) {
            return Row(
              key: ValueKey(i),
              children: [
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    _updateSelectedIndex(i - 1);

                    final list = SliverReorderableList.maybeOf(context);

                    list?.startItemDragReorder(
                      index: i,
                      event: event,
                      recognizer:
                          DelayedMultiDragGestureRecognizer(debugOwner: this),
                    );
                    _PointerSmuggler(debugOwner: this)
                      ..onStart = ((d) {
                        // the wait time has passed and the drag has
                        // started
                        setState(() {
                          _dragInProgress = true;
                        });
                        return;
                      })
                      ..addPointer(event);
                  },
                  onPointerUp: (e) {
                    setState(() {
                      _dragInProgress = false;
                    });
                  },
                  child: children[i],
                ),

                // no plus icons for the invisible boxes
                if (i != 0 && i != children.length - 1) _buildAddItemIcon(i),
              ],
            );
          },
          proxyDecorator: (child, index, animation) {
            // move and scale the dragged item
            var align = AlignmentTween(
              begin: Alignment.centerLeft,
              end: Alignment.center,
            ).animate(animation);
            var size = Tween(
              begin: 1.0,
              end: 1.1,
            ).animate(animation);

            return AlignTransition(
              alignment: align,
              child: ScaleTransition(
                scale: size,
                child: Material(
                  elevation: 4,
                  child: widget.itemBuilder(
                    _itemMaxWidth,
                    index - 1,
                    true,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAddItemIcon(int index) {
    // once we have 10 items, don't allow anymore items to be built
    if (widget.numItems < 10) {
      return AnimatedOpacity(
        opacity: _dragInProgress ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 250),
        child: IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.add),
          onPressed: () async {
            await widget.addItemAt(index);
            setState(() {
              _updateSelectedIndex(index);

              _scrollToBox(index);
            });
          },
        ),
      );
    } else {
      return SizedBox(
        width: _iconSize,
      );
    }
  }

  void _updateSelectedIndex(int index) {
    widget.onItemSelected?.call(index);
    setState(() {
      _selectedIdx = index;
    });
  }

  void _scrollToBox(int index) {
    WidgetsBinding.instance?.addPostFrameCallback((_) {
      _controller.animateTo(((_itemMaxWidth + _iconSize) * index),
          duration: Duration(milliseconds: 350), curve: Curves.linear);
    });
  }
}

/// This allows one pointer event to be used for multiple gesture recognizers.
/// This allows us to create a custom callback that is informed with the
/// recognizer starts, but doesn't event up actually doing anything with the
/// event (seeing as it's handled by the other gesture recognizer)
class _PointerSmuggler extends DelayedMultiDragGestureRecognizer {
  _PointerSmuggler(
      {Duration delay = kLongPressTimeout,
      Object? debugOwner,
      PointerDeviceKind? kind})
      : super(debugOwner: debugOwner, delay: delay, kind: kind);

  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);
  }
}
