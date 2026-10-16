import 'package:flutter/material.dart';
import 'core.dart';

class TVDashboardView extends StatefulWidget {
  final bool isSideMenuOpen;
  final VoidCallback onOpenSideMenu;
  final VoidCallback onCloseSideMenu;
  final MainSection activeSection;
  final String sectionTitle;
  final String selectedCategory;
  final List<String> sectionCategories;
  final Map<String, int> categoryCounts;
  final int totalAllCount;
  final int liveCount;
  final int movieCount;
  final int seriesCount;
  final int continueWatchingCount;
  final int favoritesCount;
  final int recentsCount;
  final List<StreamItem> displayedItems;
  final List<SeriesGroup> displayedSeries;
  final Map<String, VodProgressEntry> vodProgressMap;
  final Set<String> favoriteIds;
  final StreamItem? activeItem;
  final EpgProgramInfo? activeEpg;
  final List<StreamItem> activeQualityVariants;
  final Widget miniVideoWidget;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<MainSection> onSelectSection;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<StreamItem> onStartPreview;
  final ValueChanged<StreamItem> onOpenFullScreen;
  final ValueChanged<SeriesGroup> onSelectSeriesGroup;
  final ValueChanged<StreamItem> onToggleFavorite;
  final ValueChanged<SeriesGroup> onToggleSeriesFavorite;
  final VoidCallback onOpenSpeedTest;
  final VoidCallback onRefreshPlaylist;
  final VoidCallback onSwitchToMobileMode;
  final VoidCallback onLogout;

  const TVDashboardView({
    super.key,
    required this.isSideMenuOpen,
    required this.onOpenSideMenu,
    required this.onCloseSideMenu,
    required this.activeSection,
    required this.sectionTitle,
    required this.selectedCategory,
    required this.sectionCategories,
    required this.categoryCounts,
    required this.totalAllCount,
    required this.liveCount,
    required this.movieCount,
    required this.seriesCount,
    required this.continueWatchingCount,
    required this.favoritesCount,
    required this.recentsCount,
    required this.displayedItems,
    required this.displayedSeries,
    required this.vodProgressMap,
    required this.favoriteIds,
    required this.activeItem,
    required this.activeEpg,
    required this.activeQualityVariants,
    required this.miniVideoWidget,
    required this.searchController,
    required this.searchQuery,
    required this.onSelectSection,
    required this.onSelectCategory,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStartPreview,
    required this.onOpenFullScreen,
    required this.onSelectSeriesGroup,
    required this.onToggleFavorite,
    required this.onToggleSeriesFavorite,
    required this.onOpenSpeedTest,
    required this.onRefreshPlaylist,
    required this.onSwitchToMobileMode,
    required this.onLogout,
  });

  @override
  State<TVDashboardView> createState() => _TVDashboardViewState();
}

class _TVDashboardViewState extends State<TVDashboardView> {
  final FocusNode _activeSideMenuFocusNode = FocusNode();
  final FocusNode _selectedCategoryFocusNode = FocusNode();

  @override
  void dispose() {
    _activeSideMenuFocusNode.dispose();
    _selectedCategoryFocusNode.dispose();
    super.dispose();
  }

  /// Abre o menu lateral (se estiver fechado) e move a seleção diretamente para ele
  void _focusSideMenuNow() {
    if (!widget.isSideMenuOpen) {
      widget.onOpenSideMenu();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _activeSideMenuFocusNode.requestFocus();
      }
    });
  }

  void _focusSelectedCategoryNow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _selectedCategoryFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSeriesView = widget.activeSection == MainSection.series;
    final isMovieView = widget.activeSection == MainSection.movie ||
        widget.activeSection == MainSection.continueWatching;
    final countText = isSeriesView
        ? '${widget.displayedSeries.length} séries'
        : '${widget.displayedItems.length} itens';

    return Row(
      children: [
        // 1. MENU LATERAL COM AUTO-OCULTAÇÃO E FOCO IMEDIATO PELA SETA ESQUERDA
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: widget.isSideMenuOpen ? 215 : 18,
          decoration: const BoxDecoration(
            color: Color(0xFF0A0C12),
            border: Border(right: BorderSide(color: Colors.white10)),
          ),
          child: widget.isSideMenuOpen
              ? _buildExpandedSideMenu()
              : _buildCollapsedEdgeSensor(),
        ),

        // 2. COLUNA DE GÊNEROS / CATEGORIAS (SETA ESQUERDA SELECIONA O MENU LATERAL)
        Container(
          width: 215,
          decoration: const BoxDecoration(
            color: Color(0xFF0D0F17),
            border: Border(right: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                child: Row(
                  children: [
                    if (!widget.isSideMenuOpen)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TVIconButton(
                          icon: Icons.menu_rounded,
                          color: const Color(0xFF00E5FF),
                          size: 18,
                          onPressed: _focusSideMenuNow,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        'GÊNEROS (${widget.sectionCategories.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.sectionCategories.length,
                  itemBuilder: (context, index) {
                    final cat = widget.sectionCategories[index];
                    final count = widget.categoryCounts[cat] ?? 0;
                    final isSelected = cat == widget.selectedCategory;

                    return TVFocusableItem(
                      focusNode: isSelected ? _selectedCategoryFocusNode : null,
                      autofocus: !widget.isSideMenuOpen && isSelected,
                      onMoveLeft: _focusSideMenuNow,
                      onSelect: () => widget.onSelectCategory(cat),
                      builder: (context, isFocused) => AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00E5FF).withOpacity(0.18)
                              : isFocused
                                  ? Colors.white10
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: isFocused
                                ? const Color(0xFF00E5FF)
                                : isSelected
                                    ? const Color(0xFF00E5FF).withOpacity(0.4)
                                    : Colors.transparent,
                            width: isFocused ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cat,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected || isFocused
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF00E5FF),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // 3. ÁREA CENTRAL DE CONTEÚDOS + MONITOR VISUAL DE PRÉ-VISUALIZAÇÃO
        Expanded(
          child: Column(
            children: [
              // Barra Superior com Pesquisa Integrada
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1018),
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.sectionTitle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00E5FF),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TVFocusableItem(
                        autoScroll: false,
                        onMoveLeft: widget.isSideMenuOpen
                            ? _focusSideMenuNow
                            : _focusSelectedCategoryNow,
                        onSelect: () {
                          openTVVirtualKeyboard(
                            context: context,
                            controller: widget.searchController,
                            title: 'Pesquisar em ${widget.sectionTitle}',
                            onChanged: widget.onSearchChanged,
                          );
                        },
                        builder: (context, isFocused) => AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF12151F),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isFocused
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white12,
                              width: isFocused ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search,
                                  color: Color(0xFF00E5FF), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.searchQuery.isEmpty
                                      ? 'Aperte OK para pesquisar ao vivo em ${widget.sectionTitle}...'
                                      : 'Filtro ativo: "${widget.searchQuery}"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: widget.searchQuery.isEmpty
                                        ? Colors.white54
                                        : const Color(0xFF00E5FF),
                                    fontWeight: widget.searchQuery.isEmpty
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (widget.searchQuery.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: widget.onClearSearch,
                        builder: (context, isFocused) => Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C1D24),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isFocused
                                  ? Colors.white
                                  : Colors.redAccent.withOpacity(0.4),
                            ),
                          ),
                          child: const Text(
                            'Limpar',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Text(
                      countText,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Row(
                  children: [
                    // GRADE CENTRAL ANIMADA
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: isSeriesView
                            ? _buildTVSeriesCatalogGrid()
                            : isMovieView
                                ? _buildTVMoviesPosterGrid()
                                : _buildTVLiveChannelsGrid(),
                      ),
                    ),

                    // PAINEL DIREITO DE EXIBIÇÃO AUTOMÁTICA (NÃO PRENDE O FOCO DO CONTROLE REMOTO)
                    if (!isSeriesView)
                      ExcludeFocus(
                        child: Container(
                          width: 285,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0A0C12),
                            border:
                                Border(left: BorderSide(color: Colors.white10)),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.fiber_manual_record,
                                      color: Colors.redAccent, size: 12),
                                  SizedBox(width: 6),
                                  Text(
                                    'PRÉ-VISUALIZAÇÃO AO VIVO',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () {
                                  if (widget.activeItem != null) {
                                    widget.onOpenFullScreen(widget.activeItem!);
                                  }
                                },
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      color: Colors.black,
                                      child: widget.miniVideoWidget,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (widget.activeItem != null) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.activeItem!.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (widget.favoriteIds
                                        .contains(widget.activeItem!.id))
                                      const Icon(Icons.star_rounded,
                                          color: Colors.amber, size: 18),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.activeItem!.group,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF00E5FF)),
                                ),

                                // GUIA DE PROGRAMAÇÃO (EPG) AUTOMÁTICO
                                if (widget.activeEpg != null &&
                                    widget.activeItem!.type ==
                                        ContentType.live) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF121622),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.redAccent,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'AGORA',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                widget.activeEpg!.nowTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          child: LinearProgressIndicator(
                                            value: widget.activeEpg!.progress,
                                            minHeight: 3,
                                            backgroundColor: Colors.white12,
                                            color: const Color(0xFF00E5FF),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'A Seguir: ${widget.activeEpg!.nextTitle}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                if (widget.activeQualityVariants.length > 1) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    'RESOLUÇÕES DISPONÍVEIS NO PLAYER:',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white38,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Wrap(
                                    spacing: 5,
                                    runSpacing: 5,
                                    children:
                                        widget.activeQualityVariants.map((v) {
                                      final selected =
                                          v.id == widget.activeItem!.id;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? const Color(0xFF00E5FF)
                                              : const Color(0xFF151924),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          v.qualityTag,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: selected
                                                ? Colors.black
                                                : Colors.white70,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],

                                const Spacer(),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF121622),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: const Color(0xFF00E5FF)
                                            .withOpacity(0.25)),
                                  ),
                                  child: const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'ATALHOS DO CONTROLE:',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF00E5FF),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        '• 1º OK: Pré-visualizar canal\n• 2º OK: Abrir em Tela Cheia\n• Segurar OK: Favoritar ★\n• Seta ◄: Menu Principal',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white70,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedEdgeSensor() {
    return TVFocusableItem(
      autoScroll: false,
      onSelect: _focusSideMenuNow,
      builder: (context, isFocused) {
        if (isFocused) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusSideMenuNow();
          });
        }
        return GestureDetector(
          onTap: _focusSideMenuNow,
          child: Container(
            color: const Color(0xFF0A0C12),
            child: Center(
              child: Container(
                width: 4,
                height: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandedSideMenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 10, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.black, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'UNEX VISION',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      '${widget.totalAllCount} conteúdos',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF00E5FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              TVIconButton(
                icon: Icons.chevron_left_rounded,
                size: 18,
                onPressed: widget.onCloseSideMenu,
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: [
              _buildTVSideNavButton(
                label: 'TV ao Vivo',
                count: widget.liveCount,
                icon: Icons.live_tv_rounded,
                selected: widget.activeSection == MainSection.live,
                focusNode: widget.activeSection == MainSection.live
                    ? _activeSideMenuFocusNode
                    : null,
                onSelect: () => widget.onSelectSection(MainSection.live),
              ),
              _buildTVSideNavButton(
                label: 'Filmes',
                count: widget.movieCount,
                icon: Icons.movie_creation_outlined,
                selected: widget.activeSection == MainSection.movie,
                focusNode: widget.activeSection == MainSection.movie
                    ? _activeSideMenuFocusNode
                    : null,
                onSelect: () => widget.onSelectSection(MainSection.movie),
              ),
              _buildTVSideNavButton(
                label: 'Séries',
                count: widget.seriesCount,
                icon: Icons.video_library_outlined,
                selected: widget.activeSection == MainSection.series,
                focusNode: widget.activeSection == MainSection.series
                    ? _activeSideMenuFocusNode
                    : null,
                onSelect: () => widget.onSelectSection(MainSection.series),
              ),
              const Divider(color: Colors.white10, height: 16),
              _buildTVSideNavButton(
                label: 'Continuar',
                count: widget.continueWatchingCount,
                icon: Icons.play_circle_outline_rounded,
                selected: widget.activeSection == MainSection.continueWatching,
                focusNode:
                    widget.activeSection == MainSection.continueWatching
                        ? _activeSideMenuFocusNode
                        : null,
                onSelect: () =>
                    widget.onSelectSection(MainSection.continueWatching),
              ),
              _buildTVSideNavButton(
                label: 'Favoritos',
                count: widget.favoritesCount,
                icon: Icons.star_rounded,
                selected: widget.activeSection == MainSection.favorites,
                focusNode: widget.activeSection == MainSection.favorites
                    ? _activeSideMenuFocusNode
                    : null,
                onSelect: () => widget.onSelectSection(MainSection.favorites),
              ),
              _buildTVSideNavButton(
                label: 'Recentes',
                count: widget.recentsCount,
                icon: Icons.history_rounded,
                selected: widget.activeSection == MainSection.recents,
                focusNode: widget.activeSection == MainSection.recents
                    ? _activeSideMenuFocusNode
                    : null,
                onSelect: () => widget.onSelectSection(MainSection.recents),
              ),
              const Divider(color: Colors.white10, height: 16),
              _buildTVSideActionButton(
                label: 'Velocidade',
                icon: Icons.speed_rounded,
                color: const Color(0xFF00E5FF),
                onSelect: () {
                  widget.onCloseSideMenu();
                  widget.onOpenSpeedTest();
                },
              ),
              _buildTVSideActionButton(
                label: 'Atualizar Lista',
                icon: Icons.refresh_rounded,
                onSelect: () {
                  widget.onCloseSideMenu();
                  widget.onRefreshPlaylist();
                },
              ),
              _buildTVSideActionButton(
                label: 'Modo Celular',
                icon: Icons.smartphone_rounded,
                onSelect: widget.onSwitchToMobileMode,
              ),
              _buildTVSideActionButton(
                label: 'Trocar Conta',
                icon: Icons.logout_rounded,
                color: Colors.redAccent,
                onSelect: widget.onLogout,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTVSeriesCatalogGrid() {
    if (widget.displayedSeries.isEmpty) {
      return const Center(
        key: ValueKey('tv_empty_series'),
        child: Text('Nenhuma série encontrada neste gênero.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      key: ValueKey('tv_series_${widget.selectedCategory}'),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 175,
        mainAxisExtent: 245,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: widget.displayedSeries.length,
      itemBuilder: (context, index) {
        final series = widget.displayedSeries[index];
        final isFav = widget.favoriteIds.contains(series.id);

        return TVFocusableItem(
          onMoveLeft:
              widget.isSideMenuOpen && index == 0 ? _focusSideMenuNow : null,
          onSelect: () => widget.onSelectSeriesGroup(series),
          onLongSelect: () => widget.onToggleSeriesFavorite(series),
          builder: (context, isFocused) => buildStreamingPosterCard(
            title: series.title,
            subtitle:
                '${series.totalSeasons} Temp • ${series.totalEpisodes} Eps',
            logoUrl: series.logo,
            badgeText: series.qualityTag,
            isFocused: isFocused,
            isFavorite: isFav,
            onFavoriteTap: () => widget.onToggleSeriesFavorite(series),
            onTap: () => widget.onSelectSeriesGroup(series),
          ),
        );
      },
    );
  }

  Widget _buildTVMoviesPosterGrid() {
    if (widget.displayedItems.isEmpty) {
      return const Center(
        key: ValueKey('tv_empty_movies'),
        child: Text('Nenhum conteúdo encontrado nesta seção.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      key: ValueKey(
          'tv_movies_${widget.activeSection}_${widget.selectedCategory}'),
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 165,
        mainAxisExtent: 230,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: widget.displayedItems.length,
      itemBuilder: (context, index) {
        final movie = widget.displayedItems[index];
        final isPlaying = widget.activeItem?.id == movie.id;
        final isFav = widget.favoriteIds.contains(movie.id);
        final savedProg = widget.vodProgressMap[movie.id];

        return TVFocusableItem(
          onMoveLeft:
              widget.isSideMenuOpen && index == 0 ? _focusSideMenuNow : null,
          onSelect: () => widget.onStartPreview(movie),
          onLongSelect: () => widget.onToggleFavorite(movie),
          builder: (context, isFocused) => buildStreamingPosterCard(
            title: movie.name,
            subtitle: isPlaying
                ? '▶ OK p/ Tela Cheia'
                : savedProg != null
                    ? savedProg.formattedRemaining
                    : movie.group,
            logoUrl: movie.logo,
            badgeText: movie.qualityTag,
            isFocused: isFocused,
            isPlaying: isPlaying,
            isFavorite: isFav,
            progress: savedProg?.progress,
            onFavoriteTap: () => widget.onToggleFavorite(movie),
            onTap: () => widget.onStartPreview(movie),
          ),
        );
      },
    );
  }

  Widget _buildTVLiveChannelsGrid() {
    if (widget.displayedItems.isEmpty) {
      return const Center(
        key: ValueKey('tv_empty_live'),
        child: Text('Nenhum canal encontrado.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      key: ValueKey('tv_live_${widget.selectedCategory}'),
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 245,
        mainAxisExtent: 88,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: widget.displayedItems.length,
      itemBuilder: (context, index) {
        final item = widget.displayedItems[index];
        final isPlaying = widget.activeItem?.id == item.id;
        final isFav = widget.favoriteIds.contains(item.id);

        return TVFocusableItem(
          onMoveLeft:
              widget.isSideMenuOpen && index == 0 ? _focusSideMenuNow : null,
          onSelect: () => widget.onStartPreview(item),
          onLongSelect: () => widget.onToggleFavorite(item),
          builder: (context, isFocused) => AnimatedScale(
            scale: isFocused ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 130),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isPlaying
                    ? const Color(0xFF172238)
                    : const Color(0xFF12151F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFocused
                      ? const Color(0xFF00E5FF)
                      : isPlaying
                          ? const Color(0xFF2979FF)
                          : Colors.white10,
                  width: isFocused ? 2.2 : 1,
                ),
              ),
              child: Row(
                children: [
                  buildChannelLogo(item.logo, size: 44),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            buildQualityBadge(item.qualityTag),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                isPlaying
                                    ? '▶ OK p/ Tela Cheia'
                                    : item.group,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isPlaying
                                      ? const Color(0xFF00E5FF)
                                      : Colors.white54,
                                  fontWeight: isPlaying
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isFav)
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTVSideNavButton({
    required String label,
    required int count,
    required IconData icon,
    required bool selected,
    required VoidCallback onSelect,
    FocusNode? focusNode,
  }) {
    return TVFocusableItem(
      focusNode: focusNode,
      autofocus: selected,
      onMoveRight: _focusSelectedCategoryNow,
      onSelect: onSelect,
      builder: (context, isFocused) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF2979FF)])
              : null,
          color: selected
              ? null
              : isFocused
                  ? Colors.white10
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused ? Colors.white : Colors.transparent,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 17, color: selected ? Colors.black : Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.black : Colors.white,
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.black87 : const Color(0xFF00E5FF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTVSideActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onSelect,
    Color color = Colors.white70,
  }) {
    return TVFocusableItem(
      onMoveRight: _focusSelectedCategoryNow,
      onSelect: onSelect,
      builder: (context, isFocused) => Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isFocused ? Colors.white10 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused ? const Color(0xFF00E5FF) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
