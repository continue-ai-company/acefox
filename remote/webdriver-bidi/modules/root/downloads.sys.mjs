import {RootBiDiModule} from "chrome://remote/content/webdriver-bidi/modules/RootBiDiModule.sys.mjs";

const lazy = {};

ChromeUtils.defineESModuleGetters(lazy, {
	assert: "chrome://remote/content/shared/webdriver/Assert.sys.mjs",
	Downloads: "resource://gre/modules/Downloads.sys.mjs",
	error: "chrome://remote/content/shared/webdriver/Errors.sys.mjs",
	pprint: "chrome://remote/content/shared/Format.sys.mjs",
});

function toDownloadPayload(download) {
	return {
		id: download.guid ?? null, // 新版本有 guid；老版本可 fallback 到 target.path
		url: download.source?.url ?? null,
		referrer: download.source?.referrerInfo?.originalReferrer?.spec ?? null,
		suggestedFilename: download.target?.path?.split(/[\\/]/).pop() ?? null,
		file: download.target?.path ?? null,            // 若你不想暴露绝对路径，可去掉
		mime: download.contentType ?? null,
		totalBytes: download.totalBytes ?? null,
		receivedBytes: download.currentBytes ?? null,
		isPrivate: !!download.source?.isPrivate,
		startTime: download.startTime ?? null,
		state: download.succeeded ? "completed" :
			download.canceled ? "canceled" :
				download.error ? "failed" : "inProgress",
	};
}
class DownloadsModule extends RootBiDiModule {
	#listAll;
	#view;
	#subscribedEvents;

	constructor(messageHandler) {
		super(messageHandler);

		Cu.printStderr(`downloads.sys.mjs: DownloadsModule initedd.\n`);

		this.#listAll = null;
		this.#view=null;
		this.#subscribedEvents = new Set();
	}

	async #startLinsten() {
		if (this.#listAll) {
			return;
		}
		this.#listAll = await lazy.Downloads.getList(lazy.Downloads.ALL);
		Cu.printStderr(`downloads.sys.mjs: #startLinsten ${this.#listAll}.\n`);
		this.#view = {
			onDownloadAdded: download => {
				// 刚加入列表即视为 started（Firefox 下载对象创建即入列）
				this.#emit("downloads.downloadStarted", { download: toDownloadPayload(download) });

				// 进度/状态变化
				/*
				download.onchange = () => {
					this.#emit("downloads.downloadUpdated", { download: toDownloadPayload(download) });

					if (download.succeeded || download.canceled || download.error) {
						this.#emit("downloads.downloadFinished", {
							download: toDownloadPayload(download),
							result: download.succeeded ? "completed" :
								download.canceled ? "canceled" : "failed",
							// 可按需附带错误
							error: download.error ? {
								message: download.error.message ?? null,
								becauseBlockedByParentalControls: !!download.error.becauseBlockedByParentalControls,
								becauseBlockedByReputationCheck: !!download.error.becauseBlockedByReputationCheck,
							} : null,
						});
					}
				};*/
			},

			onDownloadChanged: download => {
				// 某些平台/保存器不会触发 onchange；兜底从这里也发 updated/finished
				const payload = toDownloadPayload(download);
				this.#emit("downloads.downloadUpdated", { download: payload });
				if (download.succeeded || download.canceled || download.error) {
					this.#emit("downloads.downloadFinished", {
						download: payload,
						result: download.succeeded ? "completed" :
							download.canceled ? "canceled" : "failed",
						error: download.error ? { message: download.error.message ?? null } : null,
					});
				}
			},

			onDownloadRemoved: download => {
				this.#emit("downloads.downloadRemoved", { download: toDownloadPayload(download) });
			},
		};

		await this.#listAll.addView(this.#view);
	}

	#subscribeEvent(event) {
		switch (event) {
			case "downloads.downloadStarted":
			case "downloads.downloadUpdated":
			case "downloads.downloadRemoved":
			case "downloads.downloadFinished":{
				self.#startLinsten();
				//this.#startListingOnRealmCreated();
				//this.#subscribedEvents.add(event);
				break;
			}
		}
	}

	#unsubscribeEvent(event) {
		switch (event) {
			case "downloads.downloadStarted": {
				//Do nothing
				//this.#stopListingOnRealmCreated();
				//this.#subscribedEvents.delete(event);
				break;
			}
			case "downloads.downloadFinished": {
				//Do nothing
				//this.#stopListingOnRealmDestroyed();
				//this.#subscribedEvents.delete(event);
				break;
			}
		}
	}

	#emit(eventName, params) {
		this.emitEvent(
			eventName,
			params
		);
	}

	static get supportedEvents() {
		Cu.printStderr(`downloads.sys.mjs: supportedEvents.\n`);
		return [
			"downloads.downloadStarted",
			"downloads.downloadUpdated",
			"downloads.downloadFinished",
			"downloads.downloadRemoved",
		];
	}
}

export const downloads = DownloadsModule;
