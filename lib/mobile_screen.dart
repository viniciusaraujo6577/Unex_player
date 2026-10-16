import 'package:flutter/material.dart';
import 'core.dart';

class MobileDashboardView extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
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
  final String accountExpDate;
  final List<StreamItem> displayedItems;
  final List<SeriesGroup> displayedSeries;
  final List<VodProgressEntry> continueWatchingEntries;
  final Map<String, VodProgressEntry> vodProgressMap;
  final Set<String> favoriteIds;
  final StreamItem? activeItem;
  final EpgProgramInfo? activeEpg;
  final bool isMiniPipFloating;
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
  final VoidCallback onEnableMiniPip;
  final VoidCallback onOpenSpeedTest;
  final VoidCallback onRefreshPlaylist;
  final VoidCallback onSwitchToTVMode;
  final VoidCallback onLogout;

  const MobileDashboardView({
    super.key,
    required this.scaffoldKey,
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
    required this.accountExpDate,
    required this.displayedItems,
    required this.displayedSeries,
    required this.continueWatchingEntries,
    required this.vodProgressMap,
    required this.favoriteIds,
    required this.activeItem,
    required this.activeEpg,
    required this.isMiniPipFloating,
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
    required this.onEnableMiniPip,
    required this.onOpenSpeedTest,
    required this.onRefreshPlaylist,
    required this.onSwitchToTVMode,
    required this.onLogout,
  });

  void _showCategoryModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Gêneros de $sectionTitle (${sectionCategories.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: sectionCategories.length,
                  itemBuilder: (context, index) {
                    final cat = sectionCategories[index];
                    final count = categoryCounts[cat] ?? 0;
                    final isSelected = cat == selectedCategory;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: isSelected,
                      selectedTileColor:
                          const Color(0xFF00E5FF).withOpacity(0.18),
                      leading: Icon(
                        Icons.folder_special_outlined,
                        color: isSelected
                            ? const Color(0xFF00E5FF)
                            : Colors.white54,
                      ),
                      title: Text(
                        cat,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        onSelectCategory(cat);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0C0E16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF14243B), Color(0xFF0C0E16)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.black, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'UNEX VISION',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF00E5FF).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.analytics_outlined,
                            size: 15, color: Color(0xFF00E5FF)),
                        const SizedBox(width: 6),
                        Text(
                          'Total da Lista: $totalAllCount conteúdos',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (accountExpDate.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Assinatura válida até: $accountExpDate',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text(
                'NAVEGAÇÃO PRINCIPAL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white38,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _buildDrawerItem(
                    title: 'TV ao Vivo',
                    count: liveCount,
                    icon: Icons.live_tv_rounded,
                    selected: activeSection == MainSection.live,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectSection(MainSection.live);
                    },
                  ),
                  _buildDrawerItem(
                    title: 'Filmes (Cinema)',
                    count: movieCount,
                    icon: Icons.movie_creation_outlined,
                    selected: activeSection == MainSection.movie,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectSection(MainSection.movie);
                    },
                  ),
                  _buildDrawerItem(
                    title: 'Séries (Catálogo)',
                    count: seriesCount,
                    icon: Icons.video_library_outlined,
                    selected: activeSection == MainSection.series,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectSection(MainSection.series);
                    },
                  ),
                  const Divider(color: Colors.white10, height: 24),
                  _buildDrawerItem(
                    title: 'Continuar Assistindo',
                    count: continueWatchingCount,
                    icon: Icons.play_circle_outline_rounded,
                    selected: activeSection == MainSection.continueWatching,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectSection(MainSection.continueWatching);
                    },
                  ),
                  _buildDrawerItem(
                    title: 'Meus Favoritos',
                    count: favoritesCount,
                    icon: Icons.star_rounded,
                    selected: activeSection == MainSection.favorites,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectSection(MainSection.favorites);
                    },
                  ),
                  _buildDrawerItem(
                    title: 'Assistidos Recentemente',
                    count: recentsCount,
                    icon: Icons.history_rounded,
                    selected: activeSection == MainSection.recents,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectSection(MainSection.recents);
                    },
                  ),
                  const Divider(color: Colors.white10, height: 24),
                  ListTile(
                    leading: const Icon(Icons.speed_rounded,
                        color: Color(0xFF00E5FF)),
                    title: const Text('Teste de Velocidade',
                        style: TextStyle(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      onOpenSpeedTest();
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.tv_rounded, color: Colors.white70),
                    title: const Text('Mudar para Modo TV Android',
                        style: TextStyle(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      onSwitchToTVMode();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded,
                        color: Colors.redAccent),
                    title: const Text('Trocar Lista / Sair',
                        style:
                            TextStyle(fontSize: 14, color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(context);
                      onLogout();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required String title,
    required int count,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                colors: [
                  const Color(0xFF00E5FF).withOpacity(0.22),
                  const Color(0xFF2979FF).withOpacity(0.08),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? const Color(0xFF00E5FF).withOpacity(0.5)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? const Color(0xFF00E5FF) : Colors.white70,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00E5FF) : Colors.black45,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.black : const Color(0xFF00E5FF),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final isSeriesView = activeSection == MainSection.series;
    final isMovieView = activeSection == MainSection.movie ||
        activeSection == MainSection.continueWatching;
    final countLabel = isSeriesView
        ? '${displayedSeries.length} séries'
        : '${displayedItems.length} itens';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1018),
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Menu Principal',
                icon: const Icon(Icons.menu_rounded,
                    color: Color(0xFF00E5FF), size: 26),
                onPressed: () => scaffoldKey.currentState?.openDrawer(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$selectedCategory • $countLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Teste de Velocidade',
                icon: const Icon(Icons.speed_rounded,
                    color: Color(0xFF00E5FF), size: 22),
                onPressed: onOpenSpeedTest,
              ),
              IconButton(
                tooltip: 'Atualizar Lista',
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white70, size: 21),
                onPressed: onRefreshPlaylist,
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: (activeItem != null &&
                  !isMiniPipFloating &&
                  !isKeyboardOpen &&
                  !isSeriesView)
              ? Column(
                  children: [
                    GestureDetector(
                      onTap: () => onOpenFullScreen(activeItem!),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              color: Colors.black,
                              child: miniVideoWidget,
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black87,
                                      Colors.transparent
                                    ],
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.circle,
                                        color: Colors.redAccent, size: 8),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${activeItem!.name} (Toque p/ Tela Cheia)',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: onEnableMiniPip,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                            Icons
                                                .picture_in_picture_alt_rounded,
                                            color: Color(0xFF00E5FF),
                                            size: 18),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () =>
                                          onOpenFullScreen(activeItem!),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E5FF),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.fullscreen_rounded,
                                                color: Colors.black, size: 18),
                                            SizedBox(width: 4),
                                            Text(
                                              'Tela Cheia',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (activeEpg != null &&
                        activeItem!.type == ContentType.live)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        color: const Color(0xFF101420),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5FF).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'EPG AGORA',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00E5FF),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${activeEpg!.nowTitle}  •  A seguir: ${activeEpg!.nextTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF12151F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Pesquisar em $sectionTitle...',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: Colors.white38),
                      prefixIcon: const Icon(Icons.search,
                          color: Color(0xFF00E5FF), size: 18),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: onClearSearch,
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _showCategoryModal(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12151F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.category_outlined,
                          color: Color(0xFF00E5FF), size: 17),
                      const SizedBox(width: 6),
                      Text(
                        'Gêneros (${sectionCategories.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: sectionCategories.length,
            itemBuilder: (context, index) {
              final cat = sectionCategories[index];
              final count = categoryCounts[cat] ?? 0;
              final isSelected = cat == selectedCategory;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text('$cat ($count)'),
                  selected: isSelected,
                  onSelected: (_) => onSelectCategory(cat),
                  selectedColor: const Color(0xFF00E5FF),
                  backgroundColor: const Color(0xFF12151F),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        if ((activeSection == MainSection.movie ||
                activeSection == MainSection.series) &&
            selectedCategory == 'Todas' &&
            searchQuery.isEmpty &&
            continueWatchingEntries.isNotEmpty)
          Container(
            height: 110,
            margin: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  child: Text(
                    '▶ CONTINUAR ASSISTINDO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF00E5FF),
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: continueWatchingEntries.length,
                    itemBuilder: (context, idx) {
                      final entry = continueWatchingEntries[idx];
                      return GestureDetector(
                        onTap: () => onOpenFullScreen(entry.item),
                        child: Container(
                          width: 210,
                          margin: const EdgeInsets.only(right: 10, top: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141926),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    const Color(0xFF00E5FF).withOpacity(0.35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  buildChannelLogo(entry.item.logo, size: 36),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          entry.formattedRemaining,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF00E5FF)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.play_circle_fill_rounded,
                                      color: Color(0xFF00E5FF), size: 22),
                                ],
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: entry.progress,
                                  minHeight: 4,
                                  backgroundColor: Colors.white12,
                                  color: const Color(0xFF00E5FF),
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
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: isSeriesView
                ? _buildSeriesPosterGrid()
                : isMovieView
                    ? _buildMoviesPosterGrid()
                    : _buildLiveChannelsList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSeriesPosterGrid() {
    if (displayedSeries.isEmpty) {
      return const Center(
        key: ValueKey('empty_series'),
        child: Text('Nenhuma série encontrada neste gênero.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      );
    }

    return GridView.builder(
      key: ValueKey('series_grid_$selectedCategory'),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.64,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: displayedSeries.length,
      itemBuilder: (context, index) {
        final series = displayedSeries[index];
        return GestureDetector(
          onTap: () => onSelectSeriesGroup(series),
          child: buildStreamingPosterCard(
            title: series.title,
            subtitle:
                '${series.totalSeasons} Temp • ${series.totalEpisodes} Eps',
            logoUrl: series.logo,
            badgeText: series.qualityTag,
            onTap: () => onSelectSeriesGroup(series),
          ),
        );
      },
    );
  }

  Widget _buildMoviesPosterGrid() {
    if (displayedItems.isEmpty) {
      return const Center(
        key: ValueKey('empty_movies'),
        child: Text('Nenhum conteúdo encontrado nesta seção.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      );
    }

    return GridView.builder(
      key: ValueKey('movies_grid_${activeSection}_$selectedCategory'),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.64,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: displayedItems.length,
      itemBuilder: (context, index) {
        final movie = displayedItems[index];
        final isPlaying = activeItem?.id == movie.id;
        final isFav = favoriteIds.contains(movie.id);
        final savedProg = vodProgressMap[movie.id];

        return GestureDetector(
          onTap: () => onStartPreview(movie),
          child: buildStreamingPosterCard(
            title: movie.name,
            subtitle: isPlaying
                ? '▶ Toque p/ Tela Cheia'
                : savedProg != null
                    ? savedProg.formattedRemaining
                    : movie.group,
            logoUrl: movie.logo,
            badgeText: movie.qualityTag,
            isPlaying: isPlaying,
            isFavorite: isFav,
            progress: savedProg?.progress,
            onFavoriteTap: () => onToggleFavorite(movie),
            onTap: () => onStartPreview(movie),
          ),
        );
      },
    );
  }

  Widget _buildLiveChannelsList() {
    if (displayedItems.isEmpty) {
      return const Center(
        key: ValueKey('empty_live'),
        child: Text('Nenhum canal encontrado nesta categoria.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      );
    }

    return ListView.builder(
      key: ValueKey('live_list_$selectedCategory'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: displayedItems.length,
      itemBuilder: (context, index) {
        final item = displayedItems[index];
        final isPlaying = activeItem?.id == item.id;
        final isFav = favoriteIds.contains(item.id);
        final savedProg = vodProgressMap[item.id];

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isPlaying
                ? const Color(0xFF172238)
                : const Color(0xFF12151F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPlaying
                  ? const Color(0xFF00E5FF)
                  : Colors.white.withOpacity(0.05),
              width: isPlaying ? 1.5 : 1.0,
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            onTap: () => onStartPreview(item),
            leading: buildChannelLogo(item.logo, size: 44),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            subtitle: Row(
              children: [
                buildQualityBadge(item.qualityTag),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isPlaying
                        ? 'No Ar • Toque novamente p/ Tela Cheia'
                        : savedProg != null
                            ? '${savedProg.formattedRemaining} • ${item.group}'
                            : item.group,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isPlaying
                          ? const Color(0xFF00E5FF)
                          : Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    isFav ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isFav ? Colors.amber : Colors.white30,
                    size: 20,
                  ),
                  onPressed: () => onToggleFavorite(item),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen_rounded,
                      color: Color(0xFF00E5FF), size: 22),
                  onPressed: () => onOpenFullScreen(item),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
