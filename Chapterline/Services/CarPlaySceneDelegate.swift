import CarPlay
import Foundation
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.add(self)

        if SettingsStore.shared.carPlayOpenPlayerOnLaunch, AppRuntime.player?.snapshot.bookID != nil {
            interfaceController.setRootTemplate(nowPlaying, animated: false, completion: nil)
            return
        }

        let tab = CPTabBarTemplate(templates: [recentTemplate(), libraryTemplate(), nowPlaying])
        interfaceController.setRootTemplate(tab, animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func recentTemplate() -> CPListTemplate {
        let book = AppRuntime.library?.continueListening
        var items: [CPListItem] = []
        if let book {
            let item = CPListItem(text: book.title, detailText: book.currentChapter?.title ?? book.author)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await AppRuntime.player?.load(book: book)
                    await AppRuntime.player?.play()
                    self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                    completion()
                }
            }
            items.append(item)
        }
        let section = CPListSection(items: items, header: "Continue", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Recent", sections: [section])
        template.tabImage = UIImage(systemName: "clock")
        template.tabTitle = "Recent"
        return template
    }

    private func libraryTemplate() -> CPListTemplate {
        let books = AppRuntime.library?.books ?? []
        let items: [CPListItem] = books.prefix(32).map { book in
            let item = CPListItem(text: book.title, detailText: book.author)
            item.handler = { [weak self] _, completion in
                self?.showChapters(for: book)
                completion()
            }
            return item
        }
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Library", sections: [section])
        template.tabImage = UIImage(systemName: "books.vertical")
        template.tabTitle = "Library"
        return template
    }

    private func showChapters(for book: Book) {
        let chapters = book.sortedChapters
        let items: [CPListItem] = chapters.map { chapter in
            let item = CPListItem(text: chapter.title, detailText: TimeMath.format(duration: chapter.start))
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await AppRuntime.player?.load(book: book)
                    await AppRuntime.player?.seek(to: chapter.start)
                    await AppRuntime.player?.play()
                    self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                    completion()
                }
            }
            return item
        }
        let template = CPListTemplate(title: book.title, sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }
}

extension CarPlaySceneDelegate: CPNowPlayingTemplateObserver {}
