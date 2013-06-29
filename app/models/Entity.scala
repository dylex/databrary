package models

import anorm._
import anorm.SqlParser.scalar
import dbrary._
import dbrary.Anorm._
import util._

private[models] final class Entity (val id : Int, name_ : String, orcid_ : Option[Orcid] = None) extends TableRow {
  override def hashCode = id
  def equals(e : Entity) = e.id == id

  private[this] var _name = name_
  def name = _name
  private[this] var _orcid = orcid_
  def orcid = _orcid

  private def args =
    Anorm.Args('id -> id, 'name -> name, 'orcid -> orcid)

  def change(name : String = _name, orcid : Option[Orcid] = _orcid)(implicit site : Site) : Unit = {
    if (name == _name && orcid == _orcid)
      return
    Audit.SQLon(AuditAction.change, "entity", "SET name = {name}, orcid = {orcid} WHERE id = {id}")(args : _*).execute()(site.db)
    _name = name
    _orcid = orcid
  }

  private[this] val _access = CachedVal[Permission.Value, Site.DB](Authorize.access_check(id)(_))
  def access(implicit db : Site.DB) : Permission.Value = _access
}

private[models] object Entity extends TableView("entity") {
  def apply(id : Int, name : String, orcid : Option[Orcid]) = id match {
    case NOBODY => Nobody
    case ROOT => Root
    case _ => new Entity(id, name, orcid)
  }
  private[this] val row = Anorm.rowMap(apply _, "id", "name", "orcid")


  def create(name : String)(implicit site : Site) : Entity = {
    val args = Anorm.Args('name -> name)
    Audit.SQLon(AuditAction.add, "entity", Anorm.insertArgs(args), "*")(args : _*).single(row)(site.db)
  }

  final val NOBODY : Int = -1
  final val ROOT   : Int = 0
  final val Nobody = new Entity(NOBODY, "Everybody")
  final val Root   = new Entity(ROOT,   "Databrary")
}
