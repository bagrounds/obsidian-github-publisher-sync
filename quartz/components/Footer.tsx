import {
  QuartzComponent,
  QuartzComponentConstructor,
  QuartzComponentProps,
} from "./types";
import style from "./styles/footer.scss";
import { version } from "../../package.json";
import { i18n } from "../i18n";

interface Options {
  links: Record<string, string>;
}

export default ((opts?: Options) => {
  const Footer: QuartzComponent = ({
    displayClass,
    cfg,
  }: QuartzComponentProps) => {
    const year = new Date().getFullYear();
    const links = opts?.links ?? [];
    return (
      <footer class={`${displayClass ?? ""}`}>
        <p>
          {"🔌 by "}
          <a href="https://quartz.jzhao.xyz/">💎Quartz</a>,{" "}
          <a href="https://obsidian.md">✍️Obsidian</a>,{" "}
          <a href="https://github.com/ObsidianPublisher/obsidian-github-publisher">
            📨Enveloppe
          </a>
        </p>
        <ul>
          {Object.entries(links).map(([text, link]) => (
            <li>
              <a href={link}>{text}</a>
            </li>
          ))}
        </ul>
        <p>© {year} Bryan Grounds</p>
      </footer>
    );
  };

  Footer.css = style;
  return Footer;
}) satisfies QuartzComponentConstructor;
