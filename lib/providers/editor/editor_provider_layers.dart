part of 'editor_provider.dart';

// ─── LayersMixin ──────────────────────────────────────────────────────────────
//
// Layer CRUD, group operations, layer ordering, composite thread cache.

mixin LayersMixin on Notifier<EditorState> {

  // Abstract declarations for shared helpers defined in EditorNotifier.
  List<(CrossStitchPattern, List<SnippetPalette>)> _buildUndoStack();
  void _saveSession();

  Timer? _opacityDebounce;
  List<Stitch> _stitchesWithAdded(List<Stitch> existing, Stitch stitch);
  // ─── Private helpers (unique to this mixin) ───────────────────────────────

  CrossStitchPattern _updateLayer(
      CrossStitchPattern pattern, String id, Layer Function(Layer) update) {
    return pattern.mapLayers((l) => l.id == id ? update(l) : l);
  }

  /// Inserts [newLayer] as a [LayerLeaf] immediately above the layer with
  /// [aboveId]. Falls back to inserting at the top if not found.
  List<LayerItem> _insertLayerAbove(
      List<LayerItem> items, Layer newLayer, String aboveId) {
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is LayerLeaf && item.layer.id == aboveId) {
        final result = [...items];
        result.insert(i + 1, LayerLeaf(layer: newLayer));
        return result;
      }
      if (item is LayerGroup) {
        final newGroupLayers =
            _insertInGroupLayers(item.layers, newLayer, aboveId);
        if (newGroupLayers != null) {
          final result = [...items];
          result[i] = item.copyWith(layers: newGroupLayers);
          return result;
        }
      }
    }
    return [LayerLeaf(layer: newLayer), ...items];
  }

  /// Returns updated group layers with [newLayer] inserted above [aboveId],
  /// or null if [aboveId] is not in this group.
  List<Layer>? _insertInGroupLayers(
      List<Layer> layers, Layer newLayer, String aboveId) {
    for (int i = 0; i < layers.length; i++) {
      if (layers[i].id == aboveId) {
        final result = [...layers];
        result.insert(i + 1, newLayer);
        return result;
      }
    }
    return null;
  }

  List<LayerItem> _removeLayer(List<LayerItem> items, String layerId) {
    final result = <LayerItem>[];
    for (final item in items) {
      if (item is LayerLeaf && item.layer.id == layerId) continue;
      if (item is LayerGroup) {
        result.add(item.copyWith(
            layers: item.layers.where((l) => l.id != layerId).toList()));
      } else {
        result.add(item);
      }
    }
    return result;
  }

  /// Moves layer [layerId] by [delta] positions in its container.
  /// Returns null if not found or no move needed.
  List<LayerItem>? _moveLayerDelta(
      List<LayerItem> items, String layerId, int delta) {
    final topIdx =
        items.indexWhere((i) => i is LayerLeaf && i.layer.id == layerId);
    if (topIdx != -1) {
      final newIdx = (topIdx + delta).clamp(0, items.length - 1);
      if (newIdx == topIdx) return null;
      final result = [...items];
      final moved = result.removeAt(topIdx);
      result.insert(newIdx, moved);
      return result;
    }
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is LayerGroup) {
        final idx = item.layers.indexWhere((l) => l.id == layerId);
        if (idx != -1) {
          final newIdx = (idx + delta).clamp(0, item.layers.length - 1);
          if (newIdx == idx) return null;
          final newLayers = [...item.layers];
          final moved = newLayers.removeAt(idx);
          newLayers.insert(newIdx, moved);
          final result = [...items];
          result[i] = item.copyWith(layers: newLayers);
          return result;
        }
      }
    }
    return null;
  }

  // ─── Layer operations ─────────────────────────────────────────────────────

  void addLayer() {
    final newLayer = Layer.create(name: 'Layer ${state.pattern.layers.length + 1}');
    final newItems = [...state.pattern.layerItems, LayerLeaf(layer: newLayer)];
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      activeLayerId: newLayer.id,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  void deleteLayer(String id) {
    if (state.pattern.layers.length <= 1) return;
    final newItems = _removeLayer(state.pattern.layerItems, id);
    final remaining = newItems.expand((item) => switch (item) {
          LayerLeaf(:final layer) => [layer],
          LayerGroup(:final layers) => layers,
        }).toList();
    String newActiveId = state.activeLayerId;
    if (newActiveId == id) {
      final visible = remaining.where((l) => l.visible);
      newActiveId = visible.isNotEmpty ? visible.last.id : remaining.last.id;
    }
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      activeLayerId: newActiveId,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  void renameLayer(String id, String name) {
    final newPattern =
        _updateLayer(state.pattern, id, (l) => l.copyWith(name: name));
    state = state.copyWith(pattern: newPattern, isDirty: true);
  }

  void toggleLayerVisible(String id) {
    final changedLayer = state.pattern.layers.firstWhere((l) => l.id == id);
    // Collect affected cells for incremental render-cache update.
    final affectedCells = <Cell>{
      for (final s in changedLayer.stitches) ?s.cellCoords,
    };
    final newPattern =
        _updateLayer(state.pattern, id, (l) => l.copyWith(visible: !l.visible));
    // Use computeLayer rather than patchAffectedLayer: visibility toggle affects
    // every stitch in the layer, so patchAffectedLayer's map-copy overhead
    // (O(total_composite_cells)) is comparable to a full recompute while also
    // paying the per-cell _resolveCell cost. computeLayer does a single forward
    // pass with fewer intermediate allocations.
    final newComposite = StitchCompositor.computeLayer(newPattern);
    // Pass dirtyCellKeys so _syncRenderCache uses updateCells instead of rebuild.
    // When other layers cover the rest of the canvas, this avoids re-processing
    // the (total_composite - affected) unchanged cells.
    state = state.copyWith(
      pattern: newPattern,
      isDirty: true,
      compositeLayer: newComposite,
      dirtyCellKeys: affectedCells.isEmpty ? null : affectedCells,
    );
  }

  void toggleLayerLocked(String id) {
    final newPattern =
        _updateLayer(state.pattern, id, (l) => l.copyWith(locked: !l.locked));
    state = state.copyWith(pattern: newPattern, isDirty: true);
  }

  void setLayerBlendMode(String id, LayerBlendMode mode) {
    final changedLayer = state.pattern.layers.firstWhere((l) => l.id == id);
    final affectedCells = <Cell>{
      for (final s in changedLayer.stitches) ?s.cellCoords,
    };
    final newPattern =
        _updateLayer(state.pattern, id, (l) => l.copyWith(blendMode: mode));
    final newComposite = StitchCompositor.computeLayer(newPattern);
    state = state.copyWith(
      pattern: newPattern,
      isDirty: true,
      compositeLayer: newComposite,
      dirtyCellKeys: affectedCells.isEmpty ? null : affectedCells,
    );
  }

  void setLayerOpacity(String id, double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    final newPattern =
        _updateLayer(state.pattern, id, (l) => l.copyWith(opacity: clamped));
    state = state.copyWith(
        pattern: newPattern, isDirty: true, compositeLayer: null);
    _opacityDebounce?.cancel();
    _opacityDebounce =
        Timer(const Duration(milliseconds: 150), refreshCompositeCache);
  }

  /// [delta] = +1 moves layer up (toward top/front), -1 moves down.
  void moveLayer(String id, int delta) {
    final newItems = _moveLayerDelta(state.pattern.layerItems, id, delta);
    if (newItems == null) return;
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
    refreshCompositeCache();
  }

  void duplicateLayer(String id) {
    final src = state.pattern.layers.firstWhere((l) => l.id == id);
    final duplicate = Layer(
      id: const Uuid().v4(),
      name: '${src.name} copy',
      visible: src.visible,
      locked: src.locked,
      opacity: src.opacity,
      blendMode: src.blendMode,
      stitches: List<Stitch>.from(src.stitches),
    );
    final newItems = _insertLayerAbove(state.pattern.layerItems, duplicate, id);
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      activeLayerId: duplicate.id,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  /// Merges [topId]'s stitches into the layer directly below it.
  void mergeLayers(String topId) {
    final layers = state.pattern.layers;
    final topIdx = layers.indexWhere((l) => l.id == topId);
    if (topIdx <= 0) return;
    final belowIdx = topIdx - 1;
    final topLayer = layers[topIdx];
    final belowLayer = layers[belowIdx];

    var mergedStitches = [...belowLayer.stitches];
    for (final s in topLayer.stitches) {
      mergedStitches = _stitchesWithAdded(mergedStitches, s);
    }

    final mergedLayer = belowLayer.copyWith(stitches: mergedStitches);
    var newItems = state.pattern
        .mapLayers((l) => l.id == belowLayer.id ? mergedLayer : l)
        .layerItems;
    newItems = _removeLayer(newItems, topId);

    final newActiveId =
        state.activeLayerId == topId ? mergedLayer.id : state.activeLayerId;

    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      activeLayerId: newActiveId,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
    refreshCompositeCache();
  }

  void setActiveLayer(String id) {
    if (state.pattern.layers.any((l) => l.id == id)) {
      state = state.copyWith(activeLayerId: id);
      _saveSession();
    }
  }

  // ─── Group operations ─────────────────────────────────────────────────────

  void addGroup() {
    final group = LayerGroup.create();
    final newItems = [group, ...state.pattern.layerItems];
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  /// Adds a new layer into [groupId] at the top. The new layer becomes active.
  void addLayerToGroup(String groupId) {
    final newLayer =
        Layer.create(name: 'Layer ${state.pattern.layers.length + 1}');
    final newItems = state.pattern.layerItems.map((item) {
      if (item is LayerGroup && item.id == groupId) {
        return item.copyWith(layers: [...item.layers, newLayer]);
      }
      return item;
    }).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      activeLayerId: newLayer.id,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  /// Moves [layerId] to top-level, inserted below [prevTopLevelId].
  /// If [prevTopLevelId] is null, inserts at the top.
  void moveLayerToTopLevelBelow(String layerId, String? prevTopLevelId) {
    Layer? movedLayer;
    final newItems = <LayerItem>[];

    for (final item in state.pattern.layerItems) {
      if (item is LayerLeaf && item.layer.id == layerId) {
        movedLayer = item.layer;
      } else if (item is LayerGroup) {
        final lIdx = item.layers.indexWhere((l) => l.id == layerId);
        if (lIdx >= 0) {
          movedLayer = item.layers[lIdx];
          newItems.add(item.copyWith(
              layers: List<Layer>.from(item.layers)..removeAt(lIdx)));
        } else {
          newItems.add(item);
        }
      } else {
        newItems.add(item);
      }
    }
    if (movedLayer == null) return;

    if (prevTopLevelId == null) {
      newItems.add(LayerLeaf(layer: movedLayer));
    } else {
      final prevIdx = newItems.indexWhere((item) =>
          (item is LayerLeaf && item.layer.id == prevTopLevelId) ||
          (item is LayerGroup && item.id == prevTopLevelId));
      newItems.insert(
          prevIdx >= 0 ? prevIdx : newItems.length, LayerLeaf(layer: movedLayer));
    }

    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  /// Moves [layerId] into [groupId], inserted below [belowLayerId].
  void moveLayerIntoGroupBelow(
      String layerId, String groupId, String? belowLayerId) {
    Layer? movedLayer;
    final newItems = <LayerItem>[];

    for (final item in state.pattern.layerItems) {
      if (item is LayerLeaf && item.layer.id == layerId) {
        movedLayer = item.layer;
      } else if (item is LayerGroup) {
        final lIdx = item.layers.indexWhere((l) => l.id == layerId);
        if (lIdx >= 0) {
          movedLayer = item.layers[lIdx];
          newItems.add(item.copyWith(
              layers: List<Layer>.from(item.layers)..removeAt(lIdx)));
        } else {
          newItems.add(item);
        }
      } else {
        newItems.add(item);
      }
    }
    if (movedLayer == null) return;

    final finalItems = newItems.map((item) {
      if (item is LayerGroup && item.id == groupId) {
        final gl = List<Layer>.from(item.layers);
        if (belowLayerId == null) {
          gl.add(movedLayer!);
        } else {
          final belowIdx = gl.indexWhere((l) => l.id == belowLayerId);
          gl.insert(belowIdx >= 0 ? belowIdx : gl.length, movedLayer!);
        }
        return item.copyWith(layers: gl);
      }
      return item;
    }).toList();

    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: finalItems),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  void deleteGroup(String groupId) {
    final newItems = state.pattern.layerItems
        .where((i) => i is! LayerGroup || i.id != groupId)
        .toList();
    final remainingLayers = newItems.expand((item) => switch (item) {
          LayerLeaf(:final layer) => [layer],
          LayerGroup(:final layers) => layers,
        }).toList();
    if (remainingLayers.isEmpty) return;
    String newActiveId = state.activeLayerId;
    if (!remainingLayers.any((l) => l.id == newActiveId)) {
      newActiveId = remainingLayers.last.id;
    }
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      activeLayerId: newActiveId,
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  void renameGroup(String groupId, String name) {
    final newItems = state.pattern.layerItems.map((item) {
      if (item is LayerGroup && item.id == groupId) {
        return item.copyWith(name: name);
      }
      return item;
    }).toList();
    state = state.copyWith(
        pattern: state.pattern.copyWith(layerItems: newItems), isDirty: true);
  }

  void toggleGroupVisible(String groupId) {
    final newItems = state.pattern.layerItems.map((item) {
      if (item is LayerGroup && item.id == groupId) {
        return item.copyWith(groupVisible: !item.groupVisible);
      }
      return item;
    }).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      isDirty: true,
      compositeLayer: null,
    );
    refreshCompositeCache();
  }

  void toggleGroupLocked(String groupId) {
    final newItems = state.pattern.layerItems.map((item) {
      if (item is LayerGroup && item.id == groupId) {
        return item.copyWith(groupLocked: !item.groupLocked);
      }
      return item;
    }).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      isDirty: true,
    );
  }

  void toggleGroupCollapsed(String groupId) {
    final newItems = state.pattern.layerItems.map((item) {
      if (item is LayerGroup && item.id == groupId) {
        return item.copyWith(collapsed: !item.collapsed);
      }
      return item;
    }).toList();
    state = state.copyWith(pattern: state.pattern.copyWith(layerItems: newItems));
  }

  /// Dissolves the group; inserts its layers as [LayerLeaf] items in place.
  void ungroupGroup(String groupId) {
    final newItems = <LayerItem>[];
    for (final item in state.pattern.layerItems) {
      if (item is LayerGroup && item.id == groupId) {
        newItems.addAll(item.layers.map((l) => LayerLeaf(layer: l)));
      } else {
        newItems.add(item);
      }
    }
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  void moveLayerToGroup(String layerId, String groupId) {
    final layer = state.pattern.layers.firstWhere((l) => l.id == layerId);
    var newItems = _removeLayer(state.pattern.layerItems, layerId);
    newItems = newItems.map((item) {
      if (item is LayerGroup && item.id == groupId) {
        return item.copyWith(layers: [...item.layers, layer]);
      }
      return item;
    }).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  /// Removes [layerId] from [groupId] and inserts it as a [LayerLeaf]
  /// immediately below the group in the top-level list.
  void moveLayerOutOfGroup(String layerId, String groupId) {
    final layer = state.pattern.layers.firstWhere((l) => l.id == layerId);
    final newItems = <LayerItem>[];
    for (final item in state.pattern.layerItems) {
      if (item is LayerGroup && item.id == groupId) {
        newItems.add(item.copyWith(
            layers: item.layers.where((l) => l.id != layerId).toList()));
        newItems.add(LayerLeaf(layer: layer));
      } else {
        newItems.add(item);
      }
    }
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  void reorderTopLevel(int oldIndex, int newIndex) {
    final items = [...state.pattern.layerItems];
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: items),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  void reorderWithinGroup(String groupId, int oldIndex, int newIndex) {
    final newItems = state.pattern.layerItems.map((item) {
      if (item is LayerGroup && item.id == groupId) {
        final layers = [...item.layers];
        final moved = layers.removeAt(oldIndex);
        layers.insert(newIndex, moved);
        return item.copyWith(layers: layers);
      }
      return item;
    }).toList();
    state = state.copyWith(
      pattern: state.pattern.copyWith(layerItems: newItems),
      undoStack: _buildUndoStack(),
      isDirty: true,
      redoStack: [],
      compositeLayer: null,
    );
  }

  // ─── Composite thread cache ────────────────────────────────────────────────

  void setShowCompositeThreads(bool value) {
    state = state.copyWith(showCompositeThreads: value);
  }

  void refreshCompositeCache() {
    final layer = StitchCompositor.computeLayer(state.pattern);
    final activeCodes = layer.fullStitches.values.map((cs) => cs.resolvedThread.dmcCode).toSet();

    final patternMap = state.pattern.threads;
    final patternSymbols = {
      for (final t in state.pattern.threads.values)
        if (t.symbol.isNotEmpty) t.symbol,
    };

    final oldRegistry = state.pattern.compositeSymbols;

    bool symbolAvailable(String sym, Set<String> used) {
      if (used.contains(sym)) return false;
      final g = symbolSimilarityGroup(sym);
      if (g < 0) return true;
      return !used.any((s) => symbolSimilarityGroup(s) == g);
    }

    String pickSymbol(List<String> freed, Set<String> used) {
      for (int i = 0; i < freed.length; i++) {
        if (symbolAvailable(freed[i], used)) return freed.removeAt(i);
      }
      for (final s in kPatternSymbols) {
        if (symbolAvailable(s, used)) return s;
      }
      return '';
    }

    final freedSymbols = <String>[
      for (final entry in oldRegistry.entries)
        if (!activeCodes.contains(entry.key) &&
            !patternMap.containsKey(entry.key) &&
            entry.value.isNotEmpty &&
            symbolAvailable(entry.value, patternSymbols))
          entry.value,
    ];

    final used = Set<String>.from(patternSymbols);
    final newRegistry = Map<String, String>.from(oldRegistry);
    bool registryChanged = false;

    for (final code in activeCodes) {
      if (patternMap.containsKey(code)) continue; // real thread — already has symbol
      final existing = newRegistry[code];
      if (existing != null && existing.isNotEmpty && symbolAvailable(existing, used)) {
        used.add(existing);
      } else {
        final sym = pickSymbol(freedSymbols, used);
        if (sym.isNotEmpty) used.add(sym);
        if (newRegistry[code] != sym) {
          newRegistry[code] = sym;
          registryChanged = true;
        }
      }
    }

    // Remove stale entries for codes no longer active and not real threads.
    for (final code in oldRegistry.keys.toList()) {
      if (!activeCodes.contains(code) && !patternMap.containsKey(code)) {
        newRegistry.remove(code);
        registryChanged = true;
      }
    }

    // Inject symbols from the resolved registry into CompositeStitch.resolvedThread.
    // StitchCompositor doesn't know about compositeSymbols, so we apply them here.
    CompositeStitch applySymbol(CompositeStitch cs) {
      final t = cs.resolvedThread;
      final sym = newRegistry[t.dmcCode] ?? t.symbol;
      if (sym == t.symbol) return cs;
      return CompositeStitch(
        stitch: cs.stitch,
        blendedColor: cs.blendedColor,
        resolvedThread: t.copyWith(symbol: sym),
        isBlended: cs.isBlended,
      );
    }

    final symbolizedLayer = CompositeLayer(
      fullStitches: {
        for (final e in layer.fullStitches.entries) e.key: applySymbol(e.value),
      },
      otherStitches: [for (final cs in layer.otherStitches) applySymbol(cs)],
      backstitches: layer.backstitches,
      crossStitchEquiv: layer.crossStitchEquiv,
      backStitchEquiv: layer.backStitchEquiv,
    );

    state = state.copyWith(
      compositeLayer: symbolizedLayer,
      pattern: state.pattern.copyWith(compositeSymbols: newRegistry),
      isDirty: registryChanged || state.isDirty,
    );
  }

  /// Manually overrides the symbol for a composite thread.
  /// Returns true if applied, false if the symbol is already taken.
  bool changeCompositeSymbol(String dmcCode, String symbol) {
    final usedByOthers = {
      for (final t in state.pattern.threads.values)
        if (t.symbol.isNotEmpty) t.symbol,
      for (final entry in state.pattern.compositeSymbols.entries)
        if (entry.key != dmcCode && entry.value.isNotEmpty) entry.value,
    };
    if (usedByOthers.contains(symbol)) return false;

    final newRegistry = Map<String, String>.from(state.pattern.compositeSymbols)
      ..[dmcCode] = symbol;
    state = state.copyWith(
        pattern: state.pattern.copyWith(compositeSymbols: newRegistry));
    refreshCompositeCache();
    return true;
  }
}
